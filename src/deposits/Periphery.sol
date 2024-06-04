// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@solmate/tokens/ERC20.sol";
import "@src/interfaces/IFundValuationOracle.sol";
import "@src/interfaces/IOracle.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "./DepositWithdrawErrors.sol";
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
    UserAccountInfo,
    FundTVL
} from "./DepositWithdrawStructs.sol";
import {FundShareVault} from "./FundShareVault.sol";

interface IPeripheryCallbacks {
    function totalAssets() external view returns (uint256);
}

event AssetEnabled(address asset);

event AssetDisabled(address asset);

event AccountOpened(address indexed user, Role role);

event AccountRoleChanged(address indexed user, Role role);

event AccountPaused(address indexed user);

event AccountUnpaused(address indexed user);

event FeeRecipientUpdated(address recipient);

event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);

uint256 constant BP_DIVISOR = 10000;

contract Periphery is ERC20, IPeripheryCallbacks {
    using SafeTransferLib for ERC20;
    using MessageHashUtils for bytes;
    using Math for uint256;

    IFund immutable fund;
    IFundValuationOracle immutable fundValuationOracle;
    FundShareVault immutable vault;

    FundTVL[] public fundTvls;

    mapping(address asset => AssetPolicy policy) private assetPolicy;
    mapping(address user => UserAccountInfo) private userAccountInfo;

    uint256 public feeBps = 1500;
    uint256 public immutable UNIT;
    address public feeRecipient;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address fund_,
        address fundValuationOracle_,
        address feeRecipient_
    ) ERC20("Liquidity", "LiQ", _decimals) {
        UNIT = 10 ** _decimals;
        fund = IFund(fund_);
        fundValuationOracle = IFundValuationOracle(fundValuationOracle_);
        feeRecipient = feeRecipient_;
        vault = new FundShareVault(address(this), _name, _symbol);
    }

    modifier onlyWhenFundIsFullyDivested() {
        require(!fund.hasOpenPositions(), "FUND_NOT_FULLY_DIVESTED");
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

    /// TODO: use transient storage?
    modifier updateTvl() {
        (uint256 fundTvl,) = fundValuationOracle.getValuation();
        fundTvls.push(FundTVL(block.timestamp, fundTvl, totalSupply));
        _;
    }

    function totalAssets() external view override returns (uint256) {
        return fundTvls.length > 0 ? fundTvls[fundTvls.length - 1].totalAssets : 0;
    }

    function _fetchValuation(address asset) private view returns (uint256 assetValuation) {
        address assetOracle = fundValuationOracle.getAssetOracle(asset);

        // asset oracle must be set and have same decimals (currency) as fund valuation
        require(assetOracle != address(0), InvalidOracle_Error);

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (assetValuation,) = IOracle(assetOracle).getValuation();
    }

    function deposit(DepositOrder calldata order)
        public
        onlyWhenFundIsFullyDivested
        onlyActiveUser(order.intent.user)
        updateTvl
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

        uint256 assetValuation = _fetchValuation(order.intent.asset);

        uint256 liquidity = assetValuation.mulDiv(
            order.intent.amount, (1 ** assetToken.decimals()), Math.Rounding.Floor
        );

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

    function withdraw(WithdrawOrder calldata order)
        public
        onlyWhenFundIsFullyDivested
        onlyActiveUser(order.intent.user)
        updateTvl
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

        uint256 assetValuation = _fetchValuation(order.intent.asset);

        uint256 liquidity = assetValuation.mulDiv(
            (order.intent.amount + order.intent.relayerTip),
            (1 ** ERC20(order.intent.asset).decimals()),
            Math.Rounding.Ceil
        );

        // make sure the withdrawal is above the minimum
        require(liquidity > policy.minimumWithdrawal, InsufficientWithdraw_Error);

        // we calculate the yield given formula Cn = C0 * (1 + r) => Cn / C0 = 1 + r
        // C is denoted in terms of liquidity token
        /// @notice append `1 unit` to avoid rounding down the zero in case of negative yield
        uint256 accruedInterest = UNIT
            + vault.maxWithdraw(order.intent.user)
                / userAccountInfo[order.intent.user].despositedLiquidity;

        // there is positive yield, we need to calculate the fee
        /// @notice the fee is also applied to the relayer tip. Otherwise a user could avoid performance fees by withdrawing with
        /// a high relayer tip and low amount
        uint256 fee;
        if (accruedInterest > UNIT) {
            /// @notice fee = r * amount * (f / 10_000)
            /// given r = accruedInterest - 1 unit
            fee = (accruedInterest - UNIT).mulDiv(
                (order.intent.amount + order.intent.relayerTip) * feeBps,
                BP_DIVISOR,
                Math.Rounding.Ceil
            );
        }

        // reduce depositedLiquidity proportionally to the withdrawal
        userAccountInfo[order.intent.user].despositedLiquidity -=
            UNIT.mulDiv(liquidity, vault.maxWithdraw(order.intent.user), Math.Rounding.Ceil);

        /// withdraw liquidity from vault to periphery
        vaultShares = vault.withdraw(liquidity, address(this), order.intent.user);

        /// make sure slippage is acceptable
        require(vaultShares <= order.intent.maxSharesIn, SlippageLimit_Error);

        /// burn liquidity from periphery
        _burn(address(this), liquidity);

        /// transfer asset from fund to receiver
        require(
            fund.execTransactionFromModule(
                order.intent.asset,
                0,
                abi.encodeWithSignature(
                    "transfer(address,uint256)", order.intent.to, order.intent.amount - fee
                ),
                Enum.Operation.Call
            ),
            AssetTransfer_Error
        );

        // pay protocol fee
        if (fee > 0) {
            require(
                fund.execTransactionFromModule(
                    order.intent.asset,
                    0,
                    abi.encodeWithSignature("transfer(address,uint256)", feeRecipient, fee),
                    Enum.Operation.Call
                ),
                AssetTransfer_Error
            );
        }

        if (order.intent.relayerTip > 0) {
            require(
                fund.execTransactionFromModule(
                    order.intent.asset,
                    0,
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
