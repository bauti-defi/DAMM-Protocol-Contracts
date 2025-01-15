// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {IFund} from "@src/interfaces/IFund.sol";

/// @title IFundFactory
/// @notice Interface for deploying new funds and handling their initialization
interface IFundFactory {
    /// @notice Emitted when a new fund is deployed
    /// @param fund Address of the newly deployed fund
    /// @param deployer Address that initiated the deployment
    /// @param admins Array of initial fund admin addresses
    /// @param threshold Number of required signatures for fund operations
    /// @param safeSingleton Address of the Safe singleton contract used
    event FundDeployed(
        address indexed fund,
        address deployer,
        address[] admins,
        uint256 threshold,
        address safeSingleton
    );

    /// @notice Converts an existing Safe to a fund by setting up the callback handler
    /// @dev Must be called via delegatecall from a Safe contract
    function convertSafeToFund() external;

    /// @notice Callback function called during fund initialization
    /// @dev Should be called via delegatecall from the newly deployed fund
    function fundDeploymentCallback() external;

    /// @notice Deploys a new fund with specified configuration
    /// @param safeProxyFactory Address of the Safe proxy factory
    /// @param safeSingleton Address of the Safe singleton contract
    /// @param admins Array of initial fund admin addresses
    /// @param nonce Unique nonce for deterministic deployment
    /// @param threshold Number of required signatures for fund operations
    /// @return IFund interface of the newly deployed fund
    function deployFund(
        address safeProxyFactory,
        address safeSingleton,
        address[] memory admins,
        uint256 nonce,
        uint256 threshold
    ) external returns (IFund);
}
