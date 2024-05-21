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
    mapping(address user => Role role) private userWhitelist;
    mapping(address user => uint256) public override nonces;
    uint256 public basisPointsPerformanceFee;
    address public feeRecipient;

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

    modifier onlyUser(address user) {
        require(userWhitelist[user] != Role.NONE, "User not whitelisted");
        _;
    }

    /// @dev asset valuation and fund valuation must be denomintated in the same currency (same decimals)
    function deposit(DepositOrder calldata order) external override onlyUser(order.intent.user) {
        require(
            SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            ),
            "Invalid signature"
        );
        require(order.intent.nonce == nonces[order.intent.user]++, "Invalid nonce");
        require(order.intent.deadline >= block.timestamp, "Deadline expired");
        require(order.intent.amount > 0, "Amount must be greater than 0");

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canDeposit && policy.enabled, "Deposits are not enabled for this asset");

        if (policy.permissioned) {
            require(userWhitelist[order.intent.to] == Role.SUPER_USER, "Only super user");
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

    function withdraw(WithdrawOrder calldata order) external override onlyUser(order.intent.user) {
        require(
            SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            ),
            "Invalid signature"
        );
        require(order.intent.nonce == nonces[order.intent.user]++, "Invalid nonce");
        require(order.intent.deadline >= block.timestamp, "Deadline expired");
        require(order.intent.amount > 0, "Amount must be greater than 0");

        AssetPolicy memory policy = assetPolicy[order.intent.asset];

        require(policy.canWithdraw && policy.enabled, "Withdrawals are not enabled for this asset");

        if (policy.permissioned) {
            require(userWhitelist[order.intent.to] == Role.SUPER_USER, "Only super user");
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

        // calculate the withdrawal valuation, denominated in the same currency as the fund
        uint256 withdrawalValuation =
            order.intent.amount * assetValuation / (10 ** ERC20(order.intent.asset).decimals());

        require(
            withdrawalValuation > policy.minNominalWithdrawal * (10 ** decimals()),
            "Withdrawal too small"
        );

        // round up in favor of the fund to avoid some rounding error attacks
        uint256 sharesOwed = _convertToShares(withdrawalValuation, tvl, Math.Rounding.Ceil);

        // make sure the withdrawal is below the maximum
        require(sharesOwed <= order.intent.maxSharesIn, "slippage too high");

        // burn shares from user
        _burn(order.intent.user, sharesOwed);

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

        // get the fund's new asset balance
        uint256 endBalance = ERC20(order.intent.asset).balanceOf(address(fund));

        // check the withdrawal was successful
        require(
            startBalance == endBalance + order.intent.amount, "Withdrawal failed: amount mismatch"
        );

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

    function getUserRole(address user) public view override returns (Role) {
        return userWhitelist[user];
    }

    function enableUser(address user, Role role) public override onlyFund {
        userWhitelist[user] = role;

        emit UserEnabled(user, role);
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

    function disableUser(address user) public override onlyFund {
        userWhitelist[user] = Role.NONE;

        emit UserDisabled(user);
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
