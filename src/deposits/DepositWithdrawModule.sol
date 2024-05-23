// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/token/ERC20/IERC20.sol";
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

        epochs.push(Epoch({id: epochs.length, endTimestamp: block.timestamp + epochDuration}));
    }

    function _calculateFee(
        uint256 capitalToTax,
        uint256 userBalance,
        uint256 userDeposit,
        uint256 fundTvl,
        uint256 circulatingSupply
    ) private view returns (uint256 feeValue, uint256 sharesOwed) {
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

    function collectEpochPerformanceFees(address[] calldata from) external onlyFeeRecipient {
        require(basisPointsPerformanceFee > 0, "Fee is 0");
        require(epochs.length > 0, "No epochs");
        require(epochs[epochs.length - 1].endTimestamp < block.timestamp, "Epoch still active");

        /// @notice this will revert if fund is not completely liquid
        /// valuate the fund, fetches new fresh valuation
        (uint256 fundTvl,) = fundValuationOracle.getValuation();

        // get starting supply
        uint256 circulatingSupply = totalSupply();

        uint256 sharesOwed = 0;

        uint256 userCount = from.length;
        for (uint256 i = 0; i < userCount;) {
            UserAccountInfo memory info = userAccountInfo[from[i]];

            require(info.status != AccountStatus.NULL, "Account null");
            require(info.currentEpoch <= epochs.length - 1, "User not in past epochs");
            require(balanceOf(from[i]) > 0, "No balance");

            (uint256 feeValue, uint256 feeAsShares) = _calculateFee(
                info.depositValue, balanceOf(from[i]), info.depositValue, fundTvl, totalSupply()
            );

            // deduct fee from account deposit
            userAccountInfo[from[i]].depositValue -= feeValue;

            // set epoch to next one
            userAccountInfo[from[i]].currentEpoch = epochs.length;

            // burn user shares
            _burn(from[i], feeAsShares);

            // accumulate shares to bulk mint fee recipient later
            sharesOwed += feeAsShares;

            emit EpochFeeCollected(from[i], feeValue, feeAsShares, feeRecipient);

            unchecked {
                i++;
            }
        }

        // mint shares to fee recipient
        _mint(feeRecipient, sharesOwed);

        // invariant check
        require(totalSupply() == circulatingSupply, "Supply changed");
    }

    function withdrawFee(address asset, uint256 amount, uint256 maxSharesIn)
        external
        onlyFeeRecipient
        activeEpoch
    {
        require(assetPolicy[asset].enabled, "Asset not enabled");

        // valuate the fund, fetches new fresh valuation
        (uint256 fundTvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(asset);
        require(assetOracle != address(0), "Asset oracle not found");

        (uint256 assetValuation,) = IOracle(assetOracle).getValuation();

        uint256 withdrawalValuation =
            amount.mulDiv(assetValuation, (10 ** ERC20(asset).decimals()), Math.Rounding.Ceil);

        require(withdrawalValuation > 0, "Withdrawal too small");

        uint256 sharesOwed = _convertToShares(withdrawalValuation, fundTvl, Math.Rounding.Ceil);

        require(sharesOwed <= maxSharesIn, "slippage too high");

        _burn(feeRecipient, sharesOwed);

        // transfer from fund to fee recipient
        require(
            fund.execTransactionFromModule(
                asset,
                0,
                abi.encodeWithSignature("transfer(address,uint256)", feeRecipient, amount),
                Enum.Operation.Call
            ),
            "Withdrawal safe trx failed"
        );

        emit FeeWithdraw(feeRecipient, asset, amount, sharesOwed);
    }

    function _deposit(address asset, address user, uint256 amount, uint256 relayerTip)
        private
        returns (uint256 sharesOwed)
    {
        AssetPolicy memory policy = assetPolicy[asset];

        require(policy.canDeposit && policy.enabled, "Deposits are not enabled for this asset");

        if (policy.permissioned) {
            require(userAccountInfo[user].role == Role.SUPER_USER, "Only super user");
        }

        // valuate the fund, fetches new fresh valuation
        (uint256 fundTvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(asset);
        require(assetOracle != address(0), "Asset oracle not found");

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (uint256 assetValuation,) = IOracle(assetOracle).getValuation();

        ERC20 assetToken = ERC20(asset);

        // get the fund's current asset balance
        uint256 startBalance = assetToken.balanceOf(address(fund));

        // transfer from user to fund
        IERC20(assetToken).safeTransferFrom(user, address(fund), amount);

        // pay relay tip if any
        if (relayerTip > 0) {
            IERC20(assetToken).safeTransferFrom(user, msg.sender, relayerTip);
        }

        // get the fund's new asset balance
        uint256 endBalance = assetToken.balanceOf(address(fund));

        // check the deposit was successful
        require(endBalance == startBalance + amount, "Deposit failed");

        // calculate the deposit valuation, denominated in the same currency as the fund
        uint256 depositValuation = amount * assetValuation / (10 ** assetToken.decimals());

        // make sure the deposit is above the minimum
        require(
            depositValuation > policy.minNominalDeposit * (10 ** decimals()), "Deposit too small"
        );

        // increment users deposit value
        userAccountInfo[user].depositValue += depositValuation;

        // round down in favor of the fund to avoid some rounding error attacks
        sharesOwed = _convertToShares(depositValuation, fundTvl, Math.Rounding.Floor);

        emit Deposit(user, asset, amount, sharesOwed, msg.sender);
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

        uint256 sharesOwed = _deposit(
            order.intent.asset, order.intent.user, order.intent.amount, order.intent.relayerTip
        );

        // lets make sure slippage is acceptable
        require(sharesOwed >= order.intent.minSharesOut, "slippage too high");

        // mint shares
        _mint(order.intent.to, sharesOwed);
    }

    function _withdraw(InternalWithdraw memory withdrawInfo) private {
        AssetPolicy memory policy = assetPolicy[withdrawInfo.asset];

        require(policy.canWithdraw && policy.enabled, "Withdrawals are not enabled for this asset");

        if (policy.permissioned) {
            require(userAccountInfo[withdrawInfo.user].role == Role.SUPER_USER, "Only super user");
        }

        // valuate the fund, fetches new fresh valuation
        (uint256 fundTvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(withdrawInfo.asset);
        require(assetOracle != address(0), "Asset oracle not found");

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (uint256 assetValuation,) = IOracle(assetOracle).getValuation();

        // calculate the withdrawal valuation, denominated in the same currency as the fund
        uint256 withdrawalValuation = withdrawInfo.amount.mulDiv(
            assetValuation, (10 ** ERC20(withdrawInfo.asset).decimals()), Math.Rounding.Ceil
        );

        require(
            withdrawalValuation > policy.minNominalWithdrawal * (10 ** decimals()),
            "Withdrawal too small"
        );

        // round up in favor of the fund to avoid some rounding error attacks
        uint256 sharesOwed = _convertToShares(withdrawalValuation, fundTvl, Math.Rounding.Ceil);

        // make sure the withdrawal is below the maximum
        require(sharesOwed <= withdrawInfo.maxSharesIn, "slippage too high");

        // calculate the fee
        (uint256 performanceFee, uint256 feeAsShares) = _calculateFee(
            withdrawalValuation,
            balanceOf(withdrawInfo.user),
            userAccountInfo[withdrawInfo.user].depositValue,
            fundTvl,
            totalSupply()
        );

        // burn shares from user
        _burn(withdrawInfo.user, sharesOwed + feeAsShares);

        // decrement users deposit value
        userAccountInfo[withdrawInfo.user].depositValue -= (withdrawalValuation + performanceFee);

        // mint shares to fee recipient
        if (feeAsShares > 0) _mint(feeRecipient, feeAsShares);

        emit Withdraw(
            withdrawInfo.user,
            withdrawInfo.to,
            withdrawInfo.asset,
            withdrawInfo.amount,
            withdrawalValuation,
            sharesOwed + feeAsShares,
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

        _withdraw(
            InternalWithdraw({
                user: order.intent.user,
                to: order.intent.to,
                asset: order.intent.asset,
                amount: order.intent.amount,
                maxSharesIn: order.intent.maxSharesIn
            })
        );

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
