// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/modules/deposit/Structs.sol";
import {UnitOfAccount} from "@src/modules/deposit/UnitOfAccount.sol";
import {FundShareVault} from "@src/modules/deposit/FundShareVault.sol";

/// @title IDepositModule
/// @notice Interface for the DepositModule contract which manages deposits, withdrawals, and global asset policies for a Fund
/// @dev Each DepositModule is paired with exactly one Fund
interface IDepositModule {
    event DepositModuleSetup(
        address indexed initiator, address indexed owner, address indexed avatar, address target
    );

    event Withdraw(
        address indexed recipient,
        address asset,
        address burner,
        uint256 sharesIn,
        uint256 liquidityBurnt,
        uint256 assetAmountOut
    );

    event ShareDilution(address indexed recipient, address diluter, uint256 sharesOut);

    event GlobalAssetPolicyEnabled(address asset, AssetPolicy policy);

    event GlobalAssetPolicyDisabled(address asset);

    event NetDepositLimitUpdated(uint256 oldLimit, uint256 newLimit);

    /// @notice The Fund this DepositModule is associated with
    function fund() external returns (address);

    /// @notice The oracle used for price quotes
    function oracleRouter() external returns (IPriceOracle);

    /// @notice The internal ERC4626 LP vault
    function internalVault() external returns (FundShareVault);

    /// @notice The token used for internal fund accounting
    function unitOfAccount() external returns (UnitOfAccount);

    /// @notice The address of the LP vault
    function getVault() external returns (address);

    /// @notice The address of the unit of account token
    function getUnitOfAccountToken() external returns (address);

    /// @notice Processes a direct deposit order
    /// @param asset The asset to deposit
    /// @param assetAmountIn The amount of asset to deposit
    /// @param minSharesOut The minimum amount of shares to mint
    /// @param recipient The address to mint the shares to
    /// @return sharesOut Amount of vault shares minted
    /// @return liquidity Amount of liquidity minted
    function deposit(address asset, uint256 assetAmountIn, uint256 minSharesOut, address recipient)
        external
        returns (uint256 sharesOut, uint256 liquidity);

    /// @notice Processes a direct withdrawal order
    /// @param asset The asset to withdraw
    /// @param sharesToBurn The amount of shares to burn
    /// @param minAmountOut The minimum amount of asset to receive
    /// @param recipient The address to receive the asset
    /// @return assetAmountOut Amount of asset tokens withdrawn
    /// @return liquidity Amount of liquidity burned
    function withdraw(address asset, uint256 sharesToBurn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 assetAmountOut, uint256 liquidity);

    /// @notice Dilutes the internal vault by minting unbacked shares to the recipient
    /// @param sharesToMint The amount of shares to mint
    /// @param recipient The address to mint the shares to
    function dilute(uint256 sharesToMint, address recipient) external;

    /// @notice Updates the net deposit limit
    function setNetDepositLimit(uint256 limit) external;

    /// @notice Enables an asset for deposits and withdrawals
    /// @param asset The asset to enable
    /// @param policy The deposit/withdrawal policy for the asset
    function enableGlobalAssetPolicy(address asset, AssetPolicy memory policy) external;

    /// @notice Disables an asset for deposits and withdrawals
    /// @param asset The asset to disable
    function disableGlobalAssetPolicy(address asset) external;

    /// @notice Gets the deposit/withdrawal policy for an asset
    /// @param asset The asset to get the policy for
    /// @return The asset's policy
    function getGlobalAssetPolicy(address asset) external returns (AssetPolicy memory);

    /// @notice Pauses the periphery
    function pause() external;

    /// @notice Unpauses the periphery
    function unpause() external;

    /// @notice Sets a new pauser
    /// @dev only the owner can set a pauser
    /// @param _pauser The address of the new pauser
    function setPauser(address _pauser) external;

    /// @notice Revokes a pauser
    /// @dev only the owner can revoke a pauser
    /// @param _pauser The address of the pauser to revoke
    function revokePauser(address _pauser) external;
}
