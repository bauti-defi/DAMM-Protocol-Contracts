// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0;

import {ITokenWhitelistRegistry} from "./ITokenWhitelistRegistry.sol";

interface IRouter {
    error InvalidRecipient();
    error TokenNotWhitelisted();

    function owner() external view returns (address);

    function tokenWhitelistRegistry() external view returns (ITokenWhitelistRegistry);

    function isTokenWhitelisted(address user, address token) external view returns (bool);
}
