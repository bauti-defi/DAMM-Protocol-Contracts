// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {IFund} from "@src/interfaces/IFund.sol";

interface IFundFactory {
    event FundDeployed(
        address indexed fund,
        address deployer,
        address[] admins,
        uint256 threshold,
        address safeSingleton
    );

    function fundDeploymentCallback() external;
    function deployFund(
        address safeProxyFactory,
        address safeSingleton,
        address[] memory,
        uint256 nonce,
        uint256 threshold
    ) external returns (IFund);
}
