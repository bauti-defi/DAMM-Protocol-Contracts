// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IRouterWhitelistRegistry} from "@src/interfaces/IRouterWhitelistRegistry.sol";
import {IMulticallerWithSender} from "@src/interfaces/external/IMulticallerWithSender.sol";

interface IGnosisSafeModule {
    error InvalidRouter();
    error OnlyOwner();
    error OnlyOperator();

    event SetOperator(address indexed caller, address indexed operator, bool enabled);

    function execute(address vault, address target, uint256 value, bytes calldata data)
        external
        returns (bytes memory);

    function executeMulticall(
        address vault,
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values
    ) external returns (bytes[] memory);

    function setOperator(address operator, bool enabled) external;

    function operators(address operator) external view returns (bool);

    function owner() external view returns (address);

    function multicallerWithSender() external view returns (IMulticallerWithSender);

    function routerWhitelistRegistry() external view returns (IRouterWhitelistRegistry);
}
