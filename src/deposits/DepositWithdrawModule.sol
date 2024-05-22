// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "@src/interfaces/IFundValuationOracle.sol";
import "@src/interfaces/IFund.sol";

import "./DepositWithdrawStructs.sol";
import "@src/interfaces/IDepositWithdrawModule.sol";

contract DepositWithdrawModule is ERC20, IDepositWithdrawModule {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using MessageHashUtils for bytes;

    uint256 public constant BASIS_POINTS_GRANULARITY = 10000;

    IFund public immutable fund;
    IFundValuationOracle public immutable fundValuationOracle;

    mapping(address asset => AssetPolicy policy) private assetPolicy;
    uint256 public basisPointsPerformanceFee;
    address public feeRecipient;

    Epoch[] public epochs;
    mapping(address user => UserAccountInfo) public userAccountInfo;

    constructor(
        address fund_,
        address fundValuationOracle_,
        address feeRecipient_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        fund = IFund(fund_);
        fundValuationOracle = IFundValuationOracle(fundValuationOracle_);
        feeRecipient = feeRecipient_;
    }

    modifier onlyFund() {
        require(msg.sender == address(fund), "Only fund can call this function");
        _;
    }

    modifier onlyActiveUser(address user) {
        require(userAccountInfo[user].role != Role.NONE, "User not whitelisted");
        require(userAccountInfo[user].status == AccountStatus.ACTIVE, "Account not active");
        _;
    }

    modifier onlyFeeRecipient() {
        require(msg.sender == feeRecipient, "Only fee recipient can call this function");
        _;
    }

    modifier activeEpoch() {
        require(epochs.length > 0, "No epochs");
        require(epochs[epochs.length - 1].endTimestamp > block.timestamp, "Epoch ended");
        _;
    }

    function startEpoch(uint256 epochDuration) external onlyFund {
        require(
            epochs.length == 0 || epochs[epochs.length - 1].endTimestamp < block.timestamp,
            "Epoch not ended"
        );

        epochs.push(
            Epoch({
                id: epochs.length,
                tvl: 0,
                sharesOutstanding: 0,
                endTimestamp: block.timestamp + epochDuration
            })
        );
    }

    /// TODO: batching
    function collectFee(address account) external onlyFeeRecipient {
        require(basisPointsPerformanceFee > 0, "Fee is 0");
        require(epochs.length > 0, "No epochs");
        require(epochs[epochs.length - 1].endTimestamp < block.timestamp, "Epoch still active");

        UserAccountInfo memory info = userAccountInfo[account];

        require(info.status != AccountStatus.NULL, "Account null");
        require(info.currentEpoch <= epochs.length - 1, "User not in past epochs");
        require(balanceOf(account) > 0, "No balance");

        /// @notice this will revert if fund is not completely liquid
        /// valuate the fund, fetches new fresh valuation
        (uint256 fundTvl,) = fundValuationOracle.getValuation();
        uint256 circulatingSupply = totalSupply();

        (uint256 feeValue, uint256 sharesOwed) = _calculateFee(
            info.depositValue, balanceOf(account), info.depositValue, fundTvl, circulatingSupply
        );

        // deduct fee from account deposit
        userAccountInfo[account].depositValue -= feeValue;

        // set epoch to next one
        userAccountInfo[account].currentEpoch = epochs.length;

        _burn(account, sharesOwed);
        _mint(feeRecipient, sharesOwed);

        require(totalSupply() == circulatingSupply, "Supply changed");

        /// TODO: emit
    }

    function _calculateFee(
        uint256 capitalToTax,
        uint256 userBalance,
        uint256 userDeposit,
        uint256 fundTvl,
        uint256 circulatingSupply
    ) private returns (uint256 feeValue, uint256 sharesOwed) {
        if (basisPointsPerformanceFee == 0) return (0, 0);

        require(
            fundTvl * circulatingSupply * userDeposit * capitalToTax * userBalance > 0,
            "invariant: no zeros"
        );

        /// @dev (a/b) / (c/d) = a * d / b / c
        /// fundTvl / circulatingSupply = share price now
        /// deposit / userBalance = user share price
        uint256 accruedInterest = fundTvl * userBalance / circulatingSupply / userDeposit;

        // negative performance => no fees
        if (accruedInterest <= 1 * (10 ** decimals())) return (0, 0);

        feeValue = (accruedInterest - 1 * (10 ** decimals())).mulDiv(
            capitalToTax * basisPointsPerformanceFee, BASIS_POINTS_GRANULARITY, Math.Rounding.Ceil
        );

        sharesOwed = _convertToShares(feeValue, fundTvl, Math.Rounding.Ceil);
    }

    /// @dev asset valuation and fund valuation must be denomintated in the same currency (same decimals)
    function deposit(DepositOrder calldata order)
        external
        override
        onlyActiveUser(order.intent.user)
        activeEpoch
    {
        require(
            SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            ),
            "Invalid signature"
        );
        require(order.intent.nonce == userAccountInfo[order.intent.user].nonce++, "Invalid nonce");
        require(order.intent.deadline >= block.timestamp, "Deadline expired");
        require(order.intent.amount > 0, "Amount must be greater than 0");

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canDeposit && policy.enabled, "Deposits are not enabled for this asset");

        if (policy.permissioned) {
            require(userAccountInfo[order.intent.to].role == Role.SUPER_USER, "Only super user");
        }

        // valuate the fund, fetches new fresh valuation
        (uint256 tvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(order.intent.asset);
        require(assetOracle != address(0), "Asset oracle not found");

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (uint256 assetValuation,) = IOracle(assetOracle).getValuation();

        // get the fund's current asset balance
        uint256 startBalance = ERC20(order.intent.asset).balanceOf(address(fund));

        // transfer from user to fund
        IERC20(order.intent.asset).safeTransferFrom(
            order.intent.user, address(fund), order.intent.amount
        );

        // pay relay tip if any
        if (order.intent.relayerTip > 0) {
            IERC20(order.intent.asset).safeTransferFrom(
                order.intent.user, msg.sender, order.intent.relayerTip
            );
        }

        // get the fund's new asset balance
        uint256 endBalance = ERC20(order.intent.asset).balanceOf(address(fund));

        // check the deposit was successful
        require(endBalance == startBalance + order.intent.amount, "Deposit failed");

        // calculate the deposit valuation, denominated in the same currency as the fund
        uint256 depositValuation =
            order.intent.amount * assetValuation / (10 ** ERC20(order.intent.asset).decimals());

        // make sure the deposit is above the minimum
        require(
            depositValuation > policy.minNominalDeposit * (10 ** decimals()), "Deposit too small"
        );

        // increment users deposit value
        userAccountInfo[order.intent.user].depositValue += depositValuation;

        // round down in favor of the fund to avoid some rounding error attacks
        uint256 sharesOwed = _convertToShares(depositValuation, tvl, Math.Rounding.Floor);

        // lets make sure slippage is acceptable
        require(sharesOwed >= order.intent.minSharesOut, "slippage too high");

        // mint shares
        _mint(order.intent.to, sharesOwed);

        emit Deposit(
            order.intent.user,
            order.intent.to,
            order.intent.asset,
            order.intent.amount,
            depositValuation,
            tvl,
            msg.sender
        );
    }

    function withdraw(WithdrawOrder calldata order)
        external
        override
        onlyActiveUser(order.intent.user)
        activeEpoch
    {
        require(
            SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            ),
            "Invalid signature"
        );
        require(order.intent.nonce == userAccountInfo[order.intent.user].nonce++, "Invalid nonce");
        require(order.intent.deadline >= block.timestamp, "Deadline expired");
        require(order.intent.amount > 0, "Amount must be greater than 0");

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canWithdraw && policy.enabled, "Withdrawals are not enabled for this asset");

        if (policy.permissioned) {
            require(userAccountInfo[order.intent.to].role == Role.SUPER_USER, "Only super user");
        }

        // valuate the fund, fetches new fresh valuation
        (uint256 tvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(order.intent.asset);
        require(assetOracle != address(0), "Asset oracle not found");

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (uint256 assetValuation,) = IOracle(assetOracle).getValuation();

        // calculate the withdrawal valuation, denominated in the same currency as the fund
        uint256 withdrawalValuation = order.intent.amount.mulDiv(
            assetValuation, (10 ** ERC20(order.intent.asset).decimals()), Math.Rounding.Ceil
        );

        require(
            withdrawalValuation > policy.minNominalWithdrawal * (10 ** decimals()),
            "Withdrawal too small"
        );

        // round up in favor of the fund to avoid some rounding error attacks
        uint256 sharesOwed = _convertToShares(withdrawalValuation, tvl, Math.Rounding.Ceil);

        // make sure the withdrawal is below the maximum
        require(sharesOwed <= order.intent.maxSharesIn, "slippage too high");

        // calculate the fee
        (uint256 performanceFee, uint256 feeAsShares) = _calculateFee(
            withdrawalValuation,
            balanceOf(order.intent.user),
            userAccountInfo[order.intent.user].depositValue,
            tvl,
            totalSupply()
        );

        // decrement users deposit value
        userAccountInfo[order.intent.user].depositValue -= (withdrawalValuation + performanceFee);

        // burn shares from user
        _burn(order.intent.user, sharesOwed + feeAsShares);

        // mint shares to fee recipient
        _mint(feeRecipient, feeAsShares);

        // transfer from fund to user
        require(
            fund.execTransactionFromModule(
                order.intent.asset,
                0,
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    order.intent.to,
                    order.intent.amount - order.intent.relayerTip
                ),
                Enum.Operation.Call
            ),
            "Withdrawal safe trx failed"
        );

        // pay relay tip if any
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
                "Withdrawal safe trx failed"
            );
        }

        emit Withdraw(
            order.intent.user,
            order.intent.to,
            order.intent.asset,
            order.intent.amount,
            withdrawalValuation,
            tvl,
            msg.sender
        );
    }

    /// @notice shares cannot be transferred between users
    function transfer(address, uint256) public pure override returns (bool) {
        return false;
    }

    /// @notice shares cannot be transferred between users
    function transferFrom(address, address, uint256) public pure override returns (bool) {
        return false;
    }

    /// @notice cannot assume value is constant
    function decimals() public view override returns (uint8) {
        return fundValuationOracle.decimals() + _decimalsOffset();
    }

    function enableAsset(address asset, AssetPolicy memory policy) public override onlyFund {
        assetPolicy[asset] = policy;

        emit AssetEnabled(asset);
    }

    function disableAsset(address asset) public override onlyFund {
        assetPolicy[asset].enabled = false;

        emit AssetDisabled(asset);
    }

    function getAssetPolicy(address asset) public view override returns (AssetPolicy memory) {
        return assetPolicy[asset];
    }

    function pauseAccount(address user) public onlyFund {
        require(userAccountInfo[user].status == AccountStatus.ACTIVE, "Account not active");

        userAccountInfo[user].status = AccountStatus.PAUSED;
    }

    function unpauseAccount(address user) public onlyFund {
        require(userAccountInfo[user].status == AccountStatus.PAUSED, "Account not paused");

        userAccountInfo[user].status = AccountStatus.ACTIVE;
    }

    function updateAccountRole(address user, Role role) public onlyFund {
        require(userAccountInfo[user].status != AccountStatus.NULL, "Account is null");

        userAccountInfo[user].role = role;
    }

    function openAccount(address user, Role role) public onlyFund activeEpoch {
        require(userAccountInfo[user].status == AccountStatus.NULL, "Account already exists");

        userAccountInfo[user] = UserAccountInfo({
            currentEpoch: epochs.length - 1,
            depositValue: 0,
            nonce: 0,
            role: role,
            status: AccountStatus.ACTIVE
        });
    }

    /**
     * @dev See {IERC4626-convertToShares}.
     */
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        (uint256 tvl,) = fundValuationOracle.getValuation();
        return _convertToShares(assets, tvl, Math.Rounding.Ceil);
    }

    /**
     * @dev See {IERC4626-convertToAssets}.
     */
    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        (uint256 tvl,) = fundValuationOracle.getValuation();
        return _convertToAssets(shares, tvl, Math.Rounding.Floor);
    }

    /// @dev inspired by OpenZeppelin ERC-4626 implementation
    function _decimalsOffset() internal view virtual returns (uint8) {
        return 1;
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     * @dev This function is inspired by OpenZeppelin's ERC-4626 implementation.
     */
    function _convertToShares(uint256 assets, uint256 tvl, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        return assets.mulDiv(totalSupply() + 10 ** _decimalsOffset(), tvl + 1, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     * @dev This function is inspired by OpenZeppelin's ERC-4626 implementation.
     */
    function _convertToAssets(uint256 shares, uint256 tvl, Math.Rounding rounding)
        internal
        view
        virtual
        returns (uint256)
    {
        return shares.mulDiv(tvl + 1, totalSupply() + 10 ** _decimalsOffset(), rounding);
    }
}
