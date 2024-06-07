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

uint256 constant BP_DIVISOR = 10000;

contract Periphery is ERC20, IPeriphery {
    using SafeTransferLib for ERC20;
    using MessageHashUtils for bytes;
    using Math for uint256;

    IFund immutable fund;

    /// @dev should be a Euler Oracle Router
    IPriceOracle immutable oracleRouter;

    FundShareVault immutable vault;

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
            /// TODO: change this to not zero
            if (assets[i] == address(0)) {
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

    function deposit(DepositOrder calldata order)
        public
        onlyWhenFundIsFullyDivested
        onlyActiveUser(order.intent.user)
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

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canDeposit && policy.enabled, AssetUnavailable_Error);

        if (policy.permissioned) {
            require(userAccountInfo[order.intent.user].role == Role.SUPER_USER, OnlySuperUser_Error);
        }

        ERC20 assetToken = ERC20(order.intent.asset);

        /// transfer asset from caller to fund
        assetToken.safeTransferFrom(order.intent.user, address(fund), order.intent.amount);

        if (order.intent.relayerTip > 0) {
            assetToken.safeTransferFrom(order.intent.user, msg.sender, order.intent.relayerTip);
        }

        // calculate how much liquidity for this amount of deposited asset
        uint256 liquidity =
            oracleRouter.getQuote(order.intent.amount, order.intent.asset, address(this));

        // make sure the deposit is above the minimum
        require(liquidity > policy.minimumDeposit, InsufficientDeposit_Error);

        /// mint liquidity to periphery
        _mint(address(this), liquidity);

        /// mint shares to user using their liquidity
        shares = vault.deposit(liquidity, order.intent.user);

        // lets make sure slippage is acceptable
        require(shares >= order.intent.minSharesOut, SlippageLimit_Error);

        // update user liquidity balance
        userAccountInfo[order.intent.user].despositedLiquidity += liquidity;
    }

    // TODO: permit2 ?
    function withdraw(WithdrawOrder calldata order)
        public
        onlyWhenFundIsFullyDivested
        onlyActiveUser(order.intent.user)
        returns (uint256 vaultShares)
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

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canWithdraw && policy.enabled, AssetUnavailable_Error);

        if (policy.permissioned) {
            require(userAccountInfo[order.intent.user].role == Role.SUPER_USER, OnlySuperUser_Error);
        }

        uint256 cumAmount = order.intent.amount + order.intent.relayerTip;

        // calculate how much liquidity for this amount of withdrawed asset
        uint256 liquidity = oracleRouter.getQuote(cumAmount, order.intent.asset, address(this));

        // make sure the withdrawal is above the minimum
        require(liquidity > policy.minimumWithdrawal, InsufficientWithdraw_Error);

        /// withdraw liquidity from vault to periphery
        vaultShares = vault.withdraw(liquidity, address(this), order.intent.user);

        /// make sure slippage is acceptable
        require(vaultShares <= order.intent.maxSharesIn, SlippageLimit_Error);

        /// burn liquidity from periphery
        _burn(address(this), liquidity);

        /// transfer asset from fund to receiver
        require(
            // TODO: transfer returns a bool, check it
            // TODO: look at using SecuredTokenTransfer.sol in safe contracts
            fund.execTransactionFromModule(
                order.intent.asset,
                0,
                // TODO: abi.encodeCall
                abi.encodeWithSignature(
                    "transfer(address,uint256)", order.intent.to, order.intent.amount
                ),
                Enum.Operation.Call
            ),
            AssetTransfer_Error
        );

        if (order.intent.relayerTip > 0) {
            // TODO: transfer returns a bool, check it
            require(
                fund.execTransactionFromModule(
                    order.intent.asset,
                    0,
                    // TODO: abi.encodeCall
                    abi.encodeWithSignature(
                        "transfer(address,uint256)", msg.sender, order.intent.relayerTip
                    ),
                    Enum.Operation.Call
                ),
                AssetTransfer_Error
            );
        }
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
}
