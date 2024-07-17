// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "@src/interfaces/IFund.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/libs/Constants.sol";

import "@src/interfaces/IPeriphery.sol";
import "./UnitOfAccount.sol";
import "./Structs.sol";
import "./Errors.sol";
import "./Events.sol";
import {FundShareVault} from "./FundShareVault.sol";

uint256 constant BP_DIVISOR = 10_000;

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
        unitOfAccount.approve(address(vault), type(uint256).max);
    }

    modifier onlyWhenFundIsFullyDivested() {
        require(!fund.hasOpenPositions(), FundNotFullyDivested_Error);
        _;
    }

    modifier onlyFund() {
        require(msg.sender == address(fund), OnlyFund_Error);
        _;
    }

    modifier onlyActiveUser(address user) {
        require(userAccountInfo[user].role != Role.NONE, OnlyUser_Error);
        require(userAccountInfo[user].status == AccountStatus.ACTIVE, AccountNotActive_Error);
        _;
    }

    function totalAssets()
        external
        view
        override
        onlyWhenFundIsFullyDivested
        returns (uint256 total)
    {
        address[] memory assets = fund.getAssetsOfInterest();
        uint256 assetLength = assets.length;

        for (uint256 i = 0; i < assetLength;) {
            uint256 balance;

            /// native asset
            if (assets[i] == NATIVE_ASSET) {
                balance = address(fund).balance;
            } else {
                balance = ERC20(assets[i]).balanceOf(address(fund));
            }

            /// calculate how much liquidity for this amount of asset
            total +=
                balance > 0 ? oracleRouter.getQuote(balance, assets[i], address(unitOfAccount)) : 0;

            unchecked {
                ++i;
            }
        }
    }

    /// @dev two things must happen here.
    /// 1. we need to calculate the profit/loss from the last update. Pay fee accordingly
    /// 2. we need to update the vault's underlying assets to match the fund's valuation
    modifier update() {
        uint256 assetsInFund = this.totalAssets();
        uint256 assetsInVault = vault.totalAssets();

        /// we know that the difference between the assets in the fund and the vault is the profit/loss since last update
        /// we can calculate the performance fee based on this difference
        if (assetsInFund > assetsInVault) {
            uint256 profit = assetsInFund - assetsInVault;
            uint256 fee = feeBps > 0 ? profit.mulDiv(feeBps, BP_DIVISOR) : 0;

            /// we mint the profit to the periphery
            unitOfAccount.mint(address(this), profit);

            /// we transfer the profit (deducting the fee) into the vault
            /// this will distribute the profit to the vault's shareholders
            unitOfAccount.transfer(address(vault), profit - fee);

            /// if a positive fee has been accrued
            if (fee > 0) {
                /// we deposit the fee into the vault on behalf of the fee recipient
                vault.deposit(fee, feeRecipient);
            }
        } else if (assetsInFund < assetsInVault) {
            /// if the fund has lost value, we need to account for it
            /// by burning the difference in the vault
            unitOfAccount.burn(address(vault), assetsInVault - assetsInFund);
        }

        _;

        /// invariants
        require(this.totalAssets() == vault.totalAssets(), AssetInvariant_Error);
        require(unitOfAccount.totalSupply() == vault.totalAssets(), UnExpectedSupplyIncrease_Error);
    }

    function deposit(DepositOrder calldata order)
        public
        onlyActiveUser(order.intent.user)
        update
        returns (uint256 sharesOut)
    {
        require(
            SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            ),
            InvalidSignature_Error
        );
        require(order.intent.user != feeRecipient, OnlyNotFeeRecipient_Error);
        require(
            order.intent.nonce == userAccountInfo[order.intent.user].nonce++, InvalidNonce_Error
        );
        require(order.intent.deadline >= block.timestamp, IntentExpired_Error);
        require(order.intent.chaindId == block.chainid, InvalidChain_Error);

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canDeposit && policy.enabled, AssetUnavailable_Error);

        if (policy.permissioned) {
            require(userAccountInfo[order.intent.user].role == Role.SUPER_USER, OnlySuperUser_Error);
        }

        uint256 assetAmountIn = order.intent.amount;
        ERC20 assetToken = ERC20(order.intent.asset);

        /// if amount is 0, then deposit the user's entire balance
        if (assetAmountIn == 0) {
            assetAmountIn = assetToken.balanceOf(order.intent.user);

            /// make sure there is enough asset to cover the relayer tip
            if (order.intent.relayerTip > 0) {
                require(assetAmountIn > order.intent.relayerTip, InsufficientAmount_Error);

                /// deduct it from the amount to deposit
                assetAmountIn -= order.intent.relayerTip;
            }
        }

        /// calculate how much liquidity for this amount of deposited asset
        uint256 liquidity =
            oracleRouter.getQuote(assetAmountIn, order.intent.asset, address(unitOfAccount));

        /// make sure the deposit is above the minimum
        require(liquidity > policy.minimumDeposit, InsufficientDeposit_Error);

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            assetToken.safeTransferFrom(order.intent.user, msg.sender, order.intent.relayerTip);
        }

        /// transfer asset from user to fund
        assetToken.safeTransferFrom(order.intent.user, address(fund), assetAmountIn);

        /// mint liquidity to periphery
        unitOfAccount.mint(address(this), liquidity);

        /// mint shares to user using the liquidity that was just minted to periphery
        sharesOut = vault.deposit(liquidity, order.intent.user);

        /// lets make sure slippage is acceptable
        require(sharesOut >= order.intent.minSharesOut, SlippageLimit_Error);

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
        require(
            SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            ),
            InvalidSignature_Error
        );
        require(
            order.intent.nonce == userAccountInfo[order.intent.user].nonce++, InvalidNonce_Error
        );
        require(order.intent.deadline >= block.timestamp, IntentExpired_Error);
        require(order.intent.chaindId == block.chainid, InvalidChain_Error);

        /// withdraw liquidity from vault
        assetAmountOut = _withdraw(
            order.intent.asset, order.intent.shares, order.intent.user, order.intent.minAmountOut
        );

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            require(order.intent.relayerTip < assetAmountOut, InsufficientAmount_Error);

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
        require(msg.sender == feeRecipient, OnlyFeeRecipient_Error);

        /// withdraw liquidity from vault
        assetAmountOut = _withdraw(asset, shares, feeRecipient, minAmountOut);

        /// transfer asset from fund to feeRecipient
        _transferAssetFromFund(asset, feeRecipient, assetAmountOut);

        emit WithdrawFees(feeRecipient, asset, shares, assetAmountOut);
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
        require(
            success && (returnData.length == 0 || abi.decode(returnData, (bool))),
            AssetTransfer_Error
        );
    }

    function _withdraw(address assetOut, uint256 sharesToBurn, address user, uint256 minAmountOut)
        private
        returns (uint256 assetAmountOut)
    {
        AssetPolicy memory policy = assetPolicy[assetOut];

        require(policy.canWithdraw && policy.enabled, AssetUnavailable_Error);

        if (policy.permissioned) {
            require(userAccountInfo[user].role == Role.SUPER_USER, OnlySuperUser_Error);
        }

        /// if shares to burn is 0, then burn all shares owned by user
        if (sharesToBurn == 0) {
            sharesToBurn = vault.balanceOf(user);
        }

        /// burn vault shares in exchange for liquidity (unit of account) tokens
        uint256 liquidity = vault.redeem(sharesToBurn, address(this), user);

        /// make sure the withdrawal is above the minimum
        require(liquidity > policy.minimumWithdrawal, InsufficientWithdraw_Error);

        /// burn liquidity from periphery
        unitOfAccount.burn(address(this), liquidity);

        /// calculate how much asset for this amount of liquidity
        assetAmountOut = oracleRouter.getQuote(liquidity, address(unitOfAccount), assetOut);

        /// make sure slippage is acceptable
        require(minAmountOut == 0 || assetAmountOut >= minAmountOut, SlippageLimit_Error);
    }

    function _setFeeRecipient(address recipient) private {
        require(recipient != address(0), InvalidFeeRecipient_Error);

        address previous = feeRecipient;

        /// update the fee recipient
        feeRecipient = recipient;

        emit FeeRecipientUpdated(recipient, previous);
    }

    function setFeeRecipient(address recipient) external onlyFund {
        _setFeeRecipient(recipient);
    }

    function setFeeBps(uint256 bps) external onlyFund {
        require(bps < BP_DIVISOR, InvalidPerformanceFee_Error);
        uint256 oldFee = feeBps;
        feeBps = bps;

        emit PerformanceFeeUpdated(oldFee, bps);
    }

    function enableAsset(address asset, AssetPolicy memory policy) external onlyFund {
        require(fund.isAssetOfInterest(asset), AssetNotSupported_Error);
        require(policy.enabled, InvalidAssetPolicy_Error);

        assetPolicy[asset] = policy;

        emit AssetEnabled(asset);
    }

    function disableAsset(address asset) external onlyFund {
        assetPolicy[asset].enabled = false;

        emit AssetDisabled(asset);
    }

    function getAssetPolicy(address asset) external view returns (AssetPolicy memory) {
        return assetPolicy[asset];
    }

    function increaseNonce(uint256 increment) external onlyActiveUser(msg.sender) {
        userAccountInfo[msg.sender].nonce += increment > 0 ? increment : 1;
    }

    function getUserAccountInfo(address user) external view returns (UserAccountInfo memory) {
        return userAccountInfo[user];
    }

    function _pauseAccount(address user) private {
        require(userAccountInfo[user].status == AccountStatus.ACTIVE, AccountNotActive_Error);

        userAccountInfo[user].status = AccountStatus.PAUSED;

        emit AccountPaused(user);
    }

    function pauseAccount(address user) public onlyFund {
        _pauseAccount(user);
    }

    function unpauseAccount(address user) public onlyFund {
        require(userAccountInfo[user].status == AccountStatus.PAUSED, AccountNotPaused_Error);

        userAccountInfo[user].status = AccountStatus.ACTIVE;

        emit AccountUnpaused(user);
    }

    function updateAccountRole(address user, Role role) public onlyFund {
        require(userAccountInfo[user].status != AccountStatus.NULL, AccountNull_Error);

        userAccountInfo[user].role = role;

        emit AccountRoleChanged(user, role);
    }

    function _openAccount(address user, Role role) private {
        require(userAccountInfo[user].status == AccountStatus.NULL, AccountExists_Error);

        userAccountInfo[user] =
            UserAccountInfo({nonce: 0, role: role, status: AccountStatus.ACTIVE});

        emit AccountOpened(user, role);
    }

    function openAccount(address user, Role role) public onlyFund {
        _openAccount(user, role);
    }
}
