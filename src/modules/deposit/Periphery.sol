// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "./Errors.sol";
import "@src/interfaces/IFund.sol";
import "@solmate/utils/SafeTransferLib.sol";
import {
    DepositIntent,
    WithdrawIntent,
    WithdrawOrder,
    DepositOrder,
    Role,
    AccountStatus,
    AssetPolicy,
    UserAccountInfo
} from "./Structs.sol";
import {FundShareVault} from "./FundShareVault.sol";
import "@euler-price-oracle/interfaces/IPriceOracle.sol";
import {IPeriphery} from "@src/interfaces/IPeriphery.sol";
import "./Events.sol";
import "@src/libs/Constants.sol";

uint256 constant BP_DIVISOR = 10000;

contract Periphery is ERC20, IPeriphery {
    using SafeTransferLib for ERC20;
    using MessageHashUtils for bytes;
    using Math for uint256;

    IFund public immutable fund;

    /// @dev should be a Euler Oracle Router
    IPriceOracle public immutable oracleRouter;

    FundShareVault public immutable vault;

    mapping(address asset => AssetPolicy policy) private assetPolicy;
    mapping(address user => UserAccountInfo) private userAccountInfo;

    uint256 public feeBps = 1500;
    address public feeRecipient;

    constructor(
        string memory _vaultName,
        string memory _vaultSymbol,
        uint8 _decimals,
        address fund_,
        address oracleRouter_,
        address feeRecipient_
    ) ERC20("Liquidity", "USD", _decimals) {
        fund = IFund(fund_);
        oracleRouter = IPriceOracle(oracleRouter_);
        feeRecipient = feeRecipient_;
        vault = new FundShareVault(address(this), _vaultName, _vaultSymbol);
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

            // native asset
            if (assets[i] == NATIVE_ASSET) {
                balance = address(fund).balance;
            } else {
                balance = ERC20(assets[i]).balanceOf(address(fund));
            }

            // calculate how much liquidity for this amount of asset
            total += balance > 0 ? oracleRouter.getQuote(balance, assets[i], address(this)) : 0;

            unchecked {
                ++i;
            }
        }
    }

    /// @dev forgive me for my sins but the vault is only meant to be used by the periphery for accounting
    modifier balanceVault() {
        uint256 assetsInFund = this.totalAssets();
        uint256 assetsInVault = vault.totalAssets();

        /// The idea here is that the vault should always have the same amount of assets as the fund
        /// keep in mind that the vault assets are liquidity tokens meant to represent the assets in the fund
        if (assetsInFund > assetsInVault) {
            _mint(address(vault), assetsInFund - assetsInVault);
        } else if (assetsInFund < assetsInVault) {
            _burn(address(vault), assetsInVault - assetsInFund);
        }

        _;

        /// invariant
        require(this.totalAssets() == vault.totalAssets(), AssetInvariant_Error);
    }

    function deposit(DepositOrder calldata order)
        public
        onlyActiveUser(order.intent.user)
        balanceVault
        returns (uint256 shares)
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
        require(order.intent.amount > 0, InsufficientAmount_Error);
        require(order.intent.chaindId == block.chainid, InvalidChain_Error);

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canDeposit && policy.enabled, AssetUnavailable_Error);

        if (policy.permissioned) {
            require(userAccountInfo[order.intent.user].role == Role.SUPER_USER, OnlySuperUser_Error);
        }

        // calculate how much liquidity for this amount of deposited asset
        uint256 liquidity =
            oracleRouter.getQuote(order.intent.amount, order.intent.asset, address(this));

        // make sure the deposit is above the minimum
        require(liquidity > policy.minimumDeposit, InsufficientDeposit_Error);

        /// mint liquidity to periphery
        _mint(address(this), liquidity);

        /// mint shares to user using the liquidity that was just minted to periphery
        shares = vault.deposit(liquidity, order.intent.user);

        // lets make sure slippage is acceptable
        require(shares >= order.intent.minSharesOut, SlippageLimit_Error);

        ERC20 assetToken = ERC20(order.intent.asset);

        /// transfer asset from caller to fund
        assetToken.safeTransferFrom(order.intent.user, address(fund), order.intent.amount);

        // pay the relayer if required
        if (order.intent.relayerTip > 0) {
            assetToken.safeTransferFrom(order.intent.user, msg.sender, order.intent.relayerTip);
        }

        // update user liquidity balance
        userAccountInfo[order.intent.user].despositedLiquidity += liquidity;

        /// TODO: emit event
    }

    function _transferAsset(address asset, address to, uint256 amount) private {
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

    // TODO: permit2 ?
    function withdraw(WithdrawOrder calldata order)
        public
        onlyActiveUser(order.intent.user)
        balanceVault
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

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canWithdraw && policy.enabled, AssetUnavailable_Error);

        if (policy.permissioned) {
            require(userAccountInfo[order.intent.user].role == Role.SUPER_USER, OnlySuperUser_Error);
        }

        uint256 sharesToBurn = order.intent.shares;

        // if shares to burn is 0, then burn all shares owned by user
        if (sharesToBurn == 0) {
            sharesToBurn = vault.balanceOf(order.intent.user);
        }

        // burn shares from vault in exchange for liquidity tokens
        uint256 liquidity = vault.redeem(sharesToBurn, address(this), order.intent.user);

        // make sure the withdrawal is above the minimum
        require(liquidity > policy.minimumWithdrawal, InsufficientWithdraw_Error);

        /// burn liquidity from periphery
        _burn(address(this), liquidity);

        // calculate how much asset for this amount of liquidity
        assetAmountOut = oracleRouter.getQuote(liquidity, address(this), order.intent.asset);

        /// make sure slippage is acceptable
        require(
            order.intent.minAmountOut == 0 || assetAmountOut >= order.intent.minAmountOut,
            SlippageLimit_Error
        );

        /// transfer asset from fund to receiver
        _transferAsset(
            order.intent.asset, order.intent.to, assetAmountOut - order.intent.relayerTip
        );

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            _transferAsset(order.intent.asset, msg.sender, order.intent.relayerTip);
        }

        /// TODO: emit event
    }

    function setFeeRecipient(address recipient) external onlyFund {
        feeRecipient = recipient;

        emit FeeRecipientUpdated(recipient);
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

    function pauseAccount(address user) public onlyFund {
        require(userAccountInfo[user].status == AccountStatus.ACTIVE, AccountNotActive_Error);

        userAccountInfo[user].status = AccountStatus.PAUSED;

        emit AccountPaused(user);
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

    function openAccount(address user, Role role) public onlyFund {
        require(userAccountInfo[user].status == AccountStatus.NULL, AccountExists_Error);

        userAccountInfo[user] = UserAccountInfo({
            nonce: 0,
            despositedLiquidity: 0,
            role: role,
            status: AccountStatus.ACTIVE
        });

        emit AccountOpened(user, role);
    }

    /// @dev override to only allow vault to transfer shares
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        /// @notice only vault can transfer shares
        if (msg.sender != address(vault)) return false;

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);

        return true;
    }
}
