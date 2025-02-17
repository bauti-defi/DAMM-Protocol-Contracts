// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin-contracts/utils/math/SignedMath.sol";
import "@openzeppelin-contracts/utils/math/SafeCast.sol";
import "@solady/utils/FixedPointMathLib.sol";
import "@src/libs/Constants.sol";

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@src/libs/Errors.sol";
import "@zodiac/interfaces/IAvatar.sol";
import "./UnitOfAccount.sol";
import {FundShareVault} from "./FundShareVault.sol";
import {DepositLibs} from "./DepositLibs.sol";
import {SafeLib} from "@src/libs/SafeLib.sol";
import {Module} from "@zodiac/core/Module.sol";
import "@src/interfaces/IDepositModule.sol";

/// @title DepositModule
/// @notice Manages deposits and withdrawals from a Fund
/// @dev The module handles:
///      - Asset deposits/withdrawals through the Fund
///      - Unit of account token minting/burning
///      - ERC4626 vault share accounting
///      - Global asset policies for deposits and withdrawals
contract DepositModule is
    Module,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IDepositModule
{
    using SafeTransferLib for ERC20;
    using DepositLibs for address;
    using SafeLib for IAvatar;
    using SafeCast for uint256;
    using SignedMath for int256;
    using FixedPointMathLib for uint256;

    /// @dev The DAMM fund the periphery is associated with
    address public fund;
    /// @dev The oracle used for price quotes
    IPriceOracle public oracleRouter;
    /// @dev Common unit of account for assets and internalVault
    UnitOfAccount public unitOfAccount;
    /// @dev Used internally for yield accounting
    FundShareVault public internalVault;

    /// @dev The maximum amount of assets that can be deposited into the fund
    /// @notice fund valuation must be less than or equal to this value to accept deposits
    /// @notice default is set to type(uint256).max
    uint256 public netDepositLimit;

    /// @dev Maps assets to their deposit/withdrawal policies
    mapping(address asset => AssetPolicy policy) private assetPolicy;

    /// @notice Initializes the Periphery contract
    /// @param initializeParams Encoded parameters for the Periphery contract
    function setUp(bytes memory initializeParams) public override initializer {
        /// @dev vaultName_ Name of the ERC4626 vault
        /// @dev vaultSymbol_ Symbol of the ERC4626 vault
        /// @dev decimals_ Decimals for the unit of account token
        /// @dev vaultDecimalsOffset_ Decimals for the ERC4626 vault
        /// @dev fund_ Address of the Fund contract
        /// @dev oracleRouter_ Address of the oracle router for quotes
        (
            string memory vaultName_,
            string memory vaultSymbol_,
            uint8 decimals_,
            uint8 vaultDecimalsOffset_,
            address fund_,
            address oracleRouter_
        ) = abi.decode(initializeParams, (string, string, uint8, uint8, address, address));

        if (fund_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (oracleRouter_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }

        fund = fund_;
        avatar = fund_;
        target = fund_;

        _transferOwnership(fund_);
        __Pausable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, fund_);
        _grantRole(FUND_ROLE, fund_);
        _grantRole(PAUSER_ROLE, fund_);

        oracleRouter = IPriceOracle(oracleRouter_);
        netDepositLimit = type(uint256).max;
        unitOfAccount = new UnitOfAccount("Liquidity", "UNIT", decimals_);
        internalVault = new FundShareVault(
            address(unitOfAccount), vaultName_, vaultSymbol_, vaultDecimalsOffset_
        );

        /// @notice approve the internalVault to transfer liquidity to the deposit module
        unitOfAccount.approve(address(internalVault), type(uint256).max);

        emit DepositModuleSetup(msg.sender, fund_, fund_, fund_);
        emit AvatarSet(address(0), fund_);
        emit TargetSet(address(0), fund_);
    }

    /// @dev This modifier updates the balances of the internalVault and the fund
    /// this ensures that the internalVault's total assets are always equal to the fund's total assets
    modifier rebalanceVault() {
        _updateVaultBalance();

        _;

        _updateVaultBalance();
    }

    /// @inheritdoc IDepositModule
    function deposit(address asset, uint256 assetAmountIn, uint256 minSharesOut, address recipient)
        public
        whenNotPaused
        onlyRole(DEPOSITOR_ROLE)
        nonReentrant
        rebalanceVault
        returns (uint256 sharesOut, uint256 liquidity)
    {
        AssetPolicy memory policy = assetPolicy[asset];

        _validateAssetPolicy(policy, true);

        ERC20 assetToken = ERC20(asset);

        if (assetAmountIn == 0) {
            revert Errors.Deposit_InsufficientDeposit();
        }

        /// make sure the deposit is above the minimum
        if (assetAmountIn < policy.minimumDeposit) {
            revert Errors.Deposit_InsufficientDeposit();
        }

        /// transfer asset from depositor to fund
        assetToken.safeTransferFrom(msg.sender, fund, assetAmountIn);

        /// calculate how much liquidity for this amount of deposited asset
        liquidity = oracleRouter.getQuote(assetAmountIn, asset, address(unitOfAccount));

        /// mint liquidity to module
        unitOfAccount.mint(address(this), liquidity);

        /// mint shares to the caller using the liquidity that was just minted
        sharesOut = internalVault.deposit(liquidity, recipient);

        /// check if the net deposit limit is exceeded
        if (internalVault.totalAssets() > netDepositLimit) {
            revert Errors.Deposit_NetDepositLimitExceeded();
        }

        /// @notice this edge case is possible if a big amount of token is transferred
        /// to the fund before the deposit is processed
        if (sharesOut == 0) {
            revert Errors.Deposit_InsufficientShares();
        }

        /// lets make sure slippage is acceptable
        if (sharesOut < minSharesOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
        }
    }

    /// @inheritdoc IDepositModule
    function withdraw(address asset, uint256 sharesToBurn, uint256 minAmountOut, address recipient)
        public
        whenNotPaused
        onlyRole(WITHDRAWER_ROLE)
        nonReentrant
        rebalanceVault
        returns (uint256 assetAmountOut, uint256 liquidity)
    {
        AssetPolicy memory policy = assetPolicy[asset];

        _validateAssetPolicy(policy, false);

        if (sharesToBurn == 0) {
            revert Errors.Deposit_InsufficientWithdrawal();
        }

        /// burn internalVault shares in exchange for liquidity (unit of account) tokens
        liquidity = internalVault.redeem(sharesToBurn, address(this), msg.sender);

        /// burn liquidity from periphery
        unitOfAccount.burn(address(this), liquidity);

        /// calculate how much asset for this amount of liquidity
        assetAmountOut = oracleRouter.getQuote(liquidity, address(unitOfAccount), asset);

        /// make sure the withdrawal is above the minimum
        if (assetAmountOut == 0 || assetAmountOut < policy.minimumWithdrawal) {
            revert Errors.Deposit_InsufficientWithdrawal();
        }

        /// make sure slippage is acceptable
        ///@notice if minAmountOut is 0, then slippage is not checked
        if (minAmountOut != 0 && assetAmountOut < minAmountOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
        }

        IAvatar(fund).transferAssetFromSafeOrRevert(asset, recipient, assetAmountOut);

        emit Withdraw(recipient, asset, msg.sender, sharesToBurn, liquidity, assetAmountOut);
    }

    /// @inheritdoc IDepositModule
    function dilute(uint256 sharesToMint, address recipient)
        external
        whenNotPaused
        nonReentrant
        onlyRole(DILUTER_ROLE)
    {
        internalVault.mintUnbacked(sharesToMint, recipient);

        emit ShareDilution(recipient, msg.sender, sharesToMint);
    }

    function _validateAssetPolicy(AssetPolicy memory policy, bool isDeposit) private pure {
        if (
            (!policy.canDeposit && isDeposit) || (!policy.canWithdraw && !isDeposit)
                || !policy.enabled
        ) {
            revert Errors.Deposit_AssetUnavailable();
        }
    }

    function _updateVaultBalance() private {
        uint256 assetsInFund =
            oracleRouter.getQuote(internalVault.totalSupply(), fund, address(unitOfAccount));
        uint256 assetsInVault = internalVault.totalAssets();

        /// @notice assetsInFund is part of [0, uint256.max]
        int256 profitDelta = assetsInFund.toInt256() - assetsInVault.toInt256();

        if (profitDelta > 0) {
            /// we transfer the mint into the internalVault
            /// this will distribute the profit to the internalVault's shareholders
            unitOfAccount.mint(address(internalVault), profitDelta.abs());
        } else if (profitDelta < 0) {
            /// if the fund has lost value, we need to account for it
            /// so we decrease the internalVault's total assets to match the fund's total assets
            /// by burning the loss
            unitOfAccount.burn(address(internalVault), profitDelta.abs());
        }
    }

    /// @inheritdoc IDepositModule
    function setNetDepositLimit(uint256 limit_) external onlyRole(FUND_ROLE) {
        if (limit_ == 0) {
            revert Errors.Deposit_InvalidNetDepositLimit();
        }

        uint256 previous = netDepositLimit;

        netDepositLimit = limit_;

        emit NetDepositLimitUpdated(previous, limit_);
    }

    /// @inheritdoc IDepositModule
    function getUnitOfAccountToken() external view returns (address) {
        return address(unitOfAccount);
    }

    /// @inheritdoc IDepositModule
    function getVault() external view returns (address) {
        return address(internalVault);
    }

    /// @inheritdoc IDepositModule
    function enableGlobalAssetPolicy(address asset_, AssetPolicy memory policy_)
        external
        whenNotPaused
        onlyRole(FUND_ROLE)
    {
        if (!policy_.enabled) {
            revert Errors.Deposit_InvalidAssetPolicy();
        }

        assetPolicy[asset_] = policy_;

        emit GlobalAssetPolicyEnabled(asset_, policy_);
    }

    /// @inheritdoc IDepositModule
    function disableGlobalAssetPolicy(address asset_) external onlyRole(FUND_ROLE) {
        assetPolicy[asset_].enabled = false;

        emit GlobalAssetPolicyDisabled(asset_);
    }

    /// @inheritdoc IDepositModule
    function getGlobalAssetPolicy(address asset_) external view returns (AssetPolicy memory) {
        return assetPolicy[asset_];
    }
    /// @inheritdoc IDepositModule

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IDepositModule
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IDepositModule
    function setPauser(address _pauser) external onlyRole(FUND_ROLE) {
        _grantRole(PAUSER_ROLE, _pauser);
    }

    /// @inheritdoc IDepositModule
    function revokePauser(address _pauser) external onlyRole(FUND_ROLE) {
        _revokeRole(PAUSER_ROLE, _pauser);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControlUpgradeable)
        returns (bool)
    {
        return
            interfaceId == type(IDepositModule).interfaceId || super.supportsInterface(interfaceId);
    }
}
