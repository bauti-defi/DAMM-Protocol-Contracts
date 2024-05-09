// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "@src/interfaces/IFund.sol";
import "@src/interfaces/IFundValuationOracle.sol";
import "@src/interfaces/ISafe.sol";

interface IDAMMFund is IFund, ISafe {}

struct AssetPolicy {
    uint256 minNominalDeposit;
    uint256 minNominalWithdrawal;
    bool canDeposit;
    bool canWithdraw;
}

struct DepositIntent {
    address user;
    address to;
    address asset;
    uint256 amount;
    uint256 deadline;
    uint256 minSharesOut;
    uint256 relayerTip;
}

struct DepositOrder {
    DepositIntent intent;
    bytes signature;
}

struct WithdrawIntent {
    address user;
    address to;
    address asset;
    uint256 amount;
    uint256 deadline;
    uint256 maxSharesIn;
    uint256 relayerTip;
}

struct WithdrawOrder {
    WithdrawIntent intent;
    bytes signature;
}

// TODO: events
contract DepositWithdrawModule is ERC20 {
    using SafeERC20 for IERC20;
    using Math for uint256;
    using MessageHashUtils for bytes;

    IDAMMFund public immutable fund;
    IFundValuationOracle public immutable fundValuationOracle;

    mapping(address asset => AssetPolicy policy) public assetWhitelist;
    mapping(address user => bool enabled) public userWhitelist;

    constructor(
        address fund_,
        address fundValuationOracle_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        fund = IDAMMFund(fund_);
        fundValuationOracle = IFundValuationOracle(fundValuationOracle_);
    }

    modifier onlyFund() {
        require(msg.sender == address(fund), "Only fund can call this function");
        _;
    }

    modifier onlyUser(address user) {
        require(userWhitelist[user], "User not whitelisted");
        _;
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

    /// @dev asset valuation and fund valuation must be denomintated in the same currency (same decimals)
    function deposit(DepositOrder calldata order) public onlyUser(order.intent.user) {
        require(
            SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            ),
            "Invalid signature"
        );
        require(order.intent.deadline >= block.timestamp, "Deadline expired");
        require(order.intent.amount > 0, "Amount must be greater than 0");

        AssetPolicy memory policy = assetWhitelist[order.intent.asset];

        require(policy.canDeposit, "Deposits are not enabled for this asset");

        // valuate the fund, fetches new fresh valuation
        (uint256 tvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(order.intent.asset);
        require(assetOracle != address(0), "Asset oracle not found");

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (uint256 assetValuation,) = IOracle(assetOracle).getLatestValuation();

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
    }

    function withdraw(WithdrawOrder calldata order) public onlyUser(order.intent.user) {
        require(
            SignatureChecker.isValidSignatureNow(
                order.intent.user,
                abi.encode(order.intent).toEthSignedMessageHash(),
                order.signature
            ),
            "Invalid signature"
        );
        require(order.intent.deadline >= block.timestamp, "Deadline expired");
        require(order.intent.amount > 0, "Amount must be greater than 0");

        AssetPolicy memory policy = assetWhitelist[order.intent.asset];

        require(policy.canWithdraw, "Withdrawals are not enabled for this asset");

        // valuate the fund, fetches new fresh valuation
        (uint256 tvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(order.intent.asset);
        require(assetOracle != address(0), "Asset oracle not found");

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (uint256 assetValuation,) = IOracle(assetOracle).getLatestValuation();

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
    }

    /// @notice cannot assume value is constant
    function decimals() public view override returns (uint8) {
        return fundValuationOracle.decimals() + _decimalsOffset();
    }

    function enableAsset(address asset, AssetPolicy memory policy) public onlyFund {
        assetWhitelist[asset] = policy;
    }

    function disableAsset(address asset) public onlyFund {
        delete assetWhitelist[asset];
    }

    function enableUser(address user) public onlyFund {
        userWhitelist[user] = true;
    }

    function disableUser(address user) public onlyFund {
        delete userWhitelist[user];
    }

    /// @dev inspired by OpenZeppelin ERC-4626 implementation
    function _decimalsOffset() internal view virtual returns (uint8) {
        return 1;
    }
}
