// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@src/libs/Constants.sol";

import "@src/libs/Errors.sol";
import "@src/interfaces/IPeriphery.sol";
import "./UnitOfAccount.sol";
import "./Structs.sol";
import {FundShareVault} from "./FundShareVault.sol";

contract Periphery is IPeriphery {
    using SafeTransferLib for ERC20;
    using MessageHashUtils for bytes;
    using Math for uint256;

    /// @dev the DAMM fund the periphery is associated with
    IFund public immutable fund;
    /// @dev should be a Euler Oracle Router
    IPriceOracle public immutable oracleRouter;
    /// @dev common unit of account for assets and vault
    UnitOfAccount public immutable unitOfAccount;
    /// @dev used internally for yield accounting
    FundShareVault public immutable vault;

    mapping(address asset => AssetPolicy policy) private assetPolicy;
    mapping(address user => UserAccountInfo) private userAccountInfo;

    uint256 public feeBps = 0;
    address public feeRecipient;
    bool public paused;

    constructor(
        string memory _vaultName,
        string memory _vaultSymbol,
        uint8 _decimals,
        address fund_,
        address oracleRouter_,
        address feeRecipient_
    ) {
        fund = IFund(fund_);
        oracleRouter = IPriceOracle(oracleRouter_);
        _setFeeRecipient(feeRecipient_);

        unitOfAccount = new UnitOfAccount("Liquidity", "UNIT", _decimals);
        vault = new FundShareVault(address(unitOfAccount), _vaultName, _vaultSymbol);

        /// @notice infinite approval for the vault to manage periphery's balance
        unitOfAccount.approve(address(vault), type(uint256).max);
    }

    modifier onlyWhenFundIsFullyDivested() {
        if (fund.hasOpenPositions()) revert Errors.FundValuationOracle_FundNotFullyDivested();
        _;
    }

    modifier onlyFund() {
        if (msg.sender != address(fund)) revert Errors.OnlyFund();
        _;
    }

    modifier onlyActiveUser(address user) {
        if (userAccountInfo[user].role == Role.NONE) revert Errors.Deposit_OnlyUser();
        if (userAccountInfo[user].status != AccountStatus.ACTIVE) {
            revert Errors.Deposit_AccountNotActive();
        }
        _;
    }

    modifier notPaused() {
        if (paused) revert Errors.Deposit_ModulePaused();
        _;
    }

    /// @dev two things must happen here.
    /// 1. calculate the profit/loss since the last time this function was called.
    /// 2. strip protocol fee
    /// 3. update vault's total assets to match the fund's total assets
    modifier update() {
        uint256 assetsInFund = oracleRouter.getQuote(0, address(fund), address(unitOfAccount));
        uint256 assetsInVault = vault.totalAssets();

        /// we know that the difference between the assets in the fund and the assets in the vault
        /// is equal to the profit/loss since last update
        if (assetsInFund > assetsInVault) {
            uint256 profit = assetsInFund - assetsInVault;

            /// the performance fee is a percentage of the profit if there is any
            uint256 fee = feeBps > 0 ? profit.mulDiv(feeBps, BP_DIVISOR) : 0;

            /// we mint the profit to the periphery
            unitOfAccount.mint(address(this), profit);

            /// we transfer the profit (deducting the fee) into the vault
            /// this will distribute the profit to the vault's shareholders
            if (!unitOfAccount.transfer(address(vault), profit - fee)) {
                revert Errors.Deposit_AssetTransferFailed();
            }

            /// if a positive fee has been accrued
            if (fee > 0) {
                /// we deposit the fee into the vault on behalf of the fee recipient
                vault.deposit(fee, feeRecipient);
            }
        } else if (assetsInFund < assetsInVault) {
            /// if the fund has lost value, we need to account for it
            /// so we decrease the vault's total assets to match the fund's total assets
            /// by burning the loss
            unitOfAccount.burn(address(vault), assetsInVault - assetsInFund);
        }

        _;

        /// invariants for 'some' peace of mind
        assetsInFund = oracleRouter.getQuote(0, address(fund), address(unitOfAccount));
        assetsInVault = vault.totalAssets();
        if (unitOfAccount.totalSupply() != assetsInVault) {
            revert Errors.Deposit_SupplyInvariantViolated();
        }
        if (assetsInFund != assetsInVault) {
            revert Errors.Deposit_AssetInvariantViolated();
        }
    }

    function deposit(DepositOrder calldata order)
        public
        notPaused
        onlyActiveUser(order.intent.user)
        update
        returns (uint256 sharesOut)
    {
        if (
            !SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            )
        ) revert Errors.Deposit_InvalidSignature();
        if (order.intent.nonce != userAccountInfo[order.intent.user].nonce++) {
            revert Errors.Deposit_InvalidNonce();
        }

        if (order.intent.chaindId != block.chainid) revert Errors.Deposit_InvalidChain();
        if (order.intent.deadline < block.timestamp) revert Errors.Deposit_IntentExpired();

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        if (!policy.canDeposit || !policy.enabled) {
            revert Errors.Deposit_AssetUnavailable();
        }

        if (policy.permissioned && userAccountInfo[order.intent.user].role != Role.SUPER_USER) {
            revert Errors.Deposit_OnlySuperUser();
        }

        uint256 assetAmountIn = order.intent.amount;
        ERC20 assetToken = ERC20(order.intent.asset);

        /// if amount is 0, then deposit the user's entire balance
        if (assetAmountIn == 0) {
            assetAmountIn = assetToken.balanceOf(order.intent.user);

            /// make sure there is enough asset to cover the relayer tip
            if (order.intent.relayerTip > 0 && assetAmountIn <= order.intent.relayerTip) {
                revert Errors.Deposit_InsufficientAmount();
            }

            /// deduct it from the amount to deposit
            assetAmountIn -= order.intent.relayerTip;
        }

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            assetToken.safeTransferFrom(order.intent.user, msg.sender, order.intent.relayerTip);
        }

        /// transfer asset from user to fund
        assetToken.safeTransferFrom(order.intent.user, address(fund), assetAmountIn);

        /// calculate how much liquidity for this amount of deposited asset
        uint256 liquidity =
            oracleRouter.getQuote(assetAmountIn, order.intent.asset, address(unitOfAccount));

        /// make sure the deposit is above the minimum
        if (liquidity < policy.minimumDeposit) {
            revert Errors.Deposit_InsufficientDeposit();
        }

        /// mint liquidity to periphery
        unitOfAccount.mint(address(this), liquidity);

        /// mint shares to user using the liquidity that was just minted to periphery
        sharesOut = vault.deposit(liquidity, order.intent.user);

        /// lets make sure slippage is acceptable
        if (sharesOut < order.intent.minSharesOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
        }

        emit Deposit(
            order.intent.user,
            order.intent.asset,
            assetAmountIn,
            sharesOut,
            msg.sender,
            order.intent.relayerTip
        );
    }

    function withdraw(WithdrawOrder calldata order)
        public
        onlyActiveUser(order.intent.user)
        update
        returns (uint256 assetAmountOut)
    {
        if (
            !SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            )
        ) revert Errors.Deposit_InvalidSignature();
        if (order.intent.nonce != userAccountInfo[order.intent.user].nonce++) {
            revert Errors.Deposit_InvalidNonce();
        }

        if (order.intent.chaindId != block.chainid) revert Errors.Deposit_InvalidChain();
        if (order.intent.deadline < block.timestamp) revert Errors.Deposit_IntentExpired();

        /// withdraw liquidity from vault
        assetAmountOut = _withdraw(
            order.intent.asset, order.intent.shares, order.intent.user, order.intent.minAmountOut
        );

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            if (order.intent.relayerTip >= assetAmountOut) {
                revert Errors.Deposit_InsufficientAmount();
            }

            _transferAssetFromFund(order.intent.asset, msg.sender, order.intent.relayerTip);
        }

        /// transfer asset from fund to receiver
        _transferAssetFromFund(
            order.intent.asset, order.intent.to, assetAmountOut - order.intent.relayerTip
        );

        emit Withdraw(
            order.intent.user,
            order.intent.to,
            order.intent.asset,
            order.intent.shares,
            assetAmountOut,
            msg.sender,
            order.intent.relayerTip
        );
    }

    function withdrawFees(address asset, uint256 shares, uint256 minAmountOut)
        public
        update
        returns (uint256 assetAmountOut)
    {
        if (msg.sender != feeRecipient) {
            revert Errors.Deposit_OnlyFeeRecipient();
        }

        /// withdraw liquidity from vault
        assetAmountOut = _withdraw(asset, shares, feeRecipient, minAmountOut);

        /// transfer asset from fund to feeRecipient
        _transferAssetFromFund(asset, feeRecipient, assetAmountOut);

        emit WithdrawFees(feeRecipient, asset, shares, assetAmountOut);
    }

    function _withdraw(address assetOut, uint256 sharesToBurn, address user, uint256 minAmountOut)
        private
        returns (uint256 assetAmountOut)
    {
        AssetPolicy memory policy = assetPolicy[assetOut];

        if (!policy.canWithdraw || !policy.enabled) {
            revert Errors.Deposit_AssetUnavailable();
        }

        if (policy.permissioned && userAccountInfo[user].role != Role.SUPER_USER) {
            revert Errors.Deposit_OnlySuperUser();
        }

        /// if shares to burn is 0, then burn all shares owned by user
        if (sharesToBurn == 0) {
            sharesToBurn = vault.balanceOf(user);
        }

        /// burn vault shares in exchange for liquidity (unit of account) tokens
        uint256 liquidity = vault.redeem(sharesToBurn, address(this), user);

        /// make sure the withdrawal is above the minimum
        if (liquidity < policy.minimumWithdrawal) {
            revert Errors.Deposit_InsufficientWithdrawal();
        }

        /// burn liquidity from periphery
        unitOfAccount.burn(address(this), liquidity);

        /// calculate how much asset for this amount of liquidity
        assetAmountOut = oracleRouter.getQuote(liquidity, address(unitOfAccount), assetOut);

        /// make sure slippage is acceptable
        ///@notice if minAmountOut is 0, then slippage is not checked
        if (minAmountOut > 0 && assetAmountOut < minAmountOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
        }
    }

    function _transferAssetFromFund(address asset, address to, uint256 amount) private {
        /// call fund to transfer asset out
        (bool success, bytes memory returnData) = fund.execTransactionFromModuleReturnData(
            asset,
            0,
            abi.encodeWithSignature("transfer(address,uint256)", to, amount),
            Enum.Operation.Call
        );

        /// check transfer was successful
        if (!success || (returnData.length > 0 && !abi.decode(returnData, (bool)))) {
            revert Errors.Deposit_AssetTransferFailed();
        }
    }

    function _setFeeRecipient(address recipient) private {
        if (recipient == address(0)) {
            revert Errors.Deposit_InvalidFeeRecipient();
        }

        address previous = feeRecipient;

        /// update the fee recipient
        feeRecipient = recipient;

        emit FeeRecipientUpdated(recipient, previous);
    }

    function setFeeRecipient(address recipient) external notPaused onlyFund {
        _setFeeRecipient(recipient);
    }

    function setFeeBps(uint256 bps) external notPaused onlyFund {
        if (bps >= BP_DIVISOR) {
            revert Errors.Deposit_InvalidPerformanceFee();
        }
        uint256 oldFee = feeBps;
        feeBps = bps;

        emit PerformanceFeeUpdated(oldFee, bps);
    }

    function enableAsset(address asset, AssetPolicy memory policy) external notPaused onlyFund {
        if (!fund.isAssetOfInterest(asset)) {
            revert Errors.Deposit_AssetNotSupported();
        }
        if (!policy.enabled) {
            revert Errors.Deposit_InvalidAssetPolicy();
        }

        assetPolicy[asset] = policy;

        emit AssetEnabled(asset, policy);
    }

    function disableAsset(address asset) external notPaused onlyFund {
        assetPolicy[asset].enabled = false;

        emit AssetDisabled(asset);
    }

    function getAssetPolicy(address asset) external view returns (AssetPolicy memory) {
        return assetPolicy[asset];
    }

    function increaseNonce(uint256 increment) external notPaused onlyActiveUser(msg.sender) {
        userAccountInfo[msg.sender].nonce += increment > 0 ? increment : 1;
    }

    function getUserAccountInfo(address user) external view returns (UserAccountInfo memory) {
        return userAccountInfo[user];
    }

    function _pauseAccount(address user) private {
        if (userAccountInfo[user].status != AccountStatus.ACTIVE) {
            revert Errors.Deposit_AccountNotActive();
        }

        userAccountInfo[user].status = AccountStatus.PAUSED;

        emit AccountPaused(user);
    }

    function pauseAccount(address user) public onlyFund {
        _pauseAccount(user);
    }

    function unpauseAccount(address user) public onlyFund {
        if (userAccountInfo[user].status != AccountStatus.PAUSED) {
            revert Errors.Deposit_AccountNotPaused();
        }

        userAccountInfo[user].status = AccountStatus.ACTIVE;

        /// lets increment the nonce to prevent delayed replay attacks
        userAccountInfo[user].nonce++;

        emit AccountUnpaused(user);
    }

    function updateAccountRole(address user, Role role) public onlyFund {
        if (userAccountInfo[user].status == AccountStatus.NULL) {
            revert Errors.Deposit_AccountNotActive();
        }
        Role currentRole = userAccountInfo[user].role;
        if (currentRole == role || role == Role.NONE) {
            revert Errors.Deposit_InvalidAccountRoleUpdate();
        }

        userAccountInfo[user].role = role;

        emit AccountRoleChanged(user, currentRole, role);
    }

    function _openAccount(address user, Role role) private {
        if (userAccountInfo[user].status != AccountStatus.NULL) {
            revert Errors.Deposit_AccountExists();
        }

        userAccountInfo[user] =
            UserAccountInfo({nonce: 0, role: role, status: AccountStatus.ACTIVE});

        emit AccountOpened(user, role);
    }

    function openAccount(address user, Role role) public onlyFund {
        _openAccount(user, role);
    }

    function pause() external onlyFund {
        paused = true;

        emit Paused();
    }

    function unpause() external onlyFund {
        paused = false;

        emit Unpaused();
    }
}
