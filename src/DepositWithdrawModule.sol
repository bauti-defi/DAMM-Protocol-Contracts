// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";
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

contract DepositWithdrawModule is ERC20 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    IDAMMFund public immutable fund;
    IFundValuationOracle public immutable fundValuationOracle;
    uint256 private minNominalDeposit = 10;
    uint256 private minNominalWithdrawal = 10;

    mapping(address asset => AssetPolicy policy) public assetWhitelist;

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

    /// TODO: add deposit whitelist
    /// TODO: support initial deposit
    /// @dev asset valuation and fund valuation must be denomintated in the same currency (same decimals)
    function deposit(address asset, uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");

        AssetPolicy memory policy = assetWhitelist[asset];

        require(policy.canDeposit, "Deposits are not enabled for this asset");

        // valuate the fund, fetches new fresh valuation
        (uint256 tvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(asset);
        require(assetOracle != address(0), "Asset oracle not found");

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (uint256 assetValuation,) = IOracle(assetOracle).getLatestValuation();

        // get the fund's current asset balance
        uint256 startBalance = ERC20(asset).balanceOf(address(fund));

        // transfer from user to fund
        IERC20(asset).safeTransferFrom(msg.sender, address(fund), amount);

        // get the fund's new asset balance
        uint256 endBalance = ERC20(asset).balanceOf(address(fund));

        // check the deposit was successful
        require(endBalance == startBalance + amount, "Deposit failed");

        // calculate the deposit valuation, denominated in the same currency as the fund
        uint256 depositValuation = amount * assetValuation / (10 ** ERC20(asset).decimals());

        require(
            depositValuation > policy.minNominalDeposit * (10 ** decimals()), "Deposit too small"
        );

        // round down in favor of the fund to avoid some rounding error attacks
        uint256 sharesOwed = _convertToShares(depositValuation, tvl, Math.Rounding.Floor);

        // mint shares to user
        _mint(msg.sender, sharesOwed);
    }

    function withdraw(address asset, uint256 amount) public {
        require(amount > 0, "Amount must be greater than 0");

        AssetPolicy memory policy = assetWhitelist[asset];

        require(policy.canWithdraw, "Withdrawals are not enabled for this asset");

        // valuate the fund, fetches new fresh valuation
        (uint256 tvl,) = fundValuationOracle.getValuation();

        address assetOracle = fundValuationOracle.getAssetOracle(asset);
        require(assetOracle != address(0), "Asset oracle not found");

        // get asset valuation, we grab latest to ensure we are using same valuation
        // as the fund's valuation
        (uint256 assetValuation,) = IOracle(assetOracle).getLatestValuation();

        // get the fund's current asset balance
        uint256 startBalance = ERC20(asset).balanceOf(address(fund));

        // calculate the withdrawal valuation, denominated in the same currency as the fund
        uint256 withdrawalValuation = amount * assetValuation / (10 ** ERC20(asset).decimals());

        require(
            withdrawalValuation > policy.minNominalWithdrawal * (10 ** decimals()),
            "Withdrawal too small"
        );

        // round down in favor of the fund to avoid some rounding error attacks
        uint256 sharesOwed = _convertToShares(withdrawalValuation, tvl, Math.Rounding.Floor);

        // burn shares from user
        _burn(msg.sender, sharesOwed);

        // transfer froms fund to user
        fund.execTransactionFromModule(
            asset,
            amount,
            abi.encodeWithSignature("transfer(address,uint256)", msg.sender, amount),
            Enum.Operation.Call
        );

        // get the fund's new asset balance
        uint256 endBalance = ERC20(asset).balanceOf(address(fund));

        // check the withdrawal was successful
        require(startBalance == endBalance + amount, "Withdrawal failed");
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

    /// @dev inspired by OpenZeppelin ERC-4626 implementation
    function _decimalsOffset() internal view virtual returns (uint8) {
        return 1;
    }
}
