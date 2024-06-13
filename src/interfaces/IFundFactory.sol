// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFund} from "@src/interfaces/IFund.sol";

interface IFundFactory {
    function fundDeploymentCallback() external;
    function deployFund(address safeProxyFactory, address safeSingleton, address[] memory, uint256)
        external
        returns (IFund);
}
