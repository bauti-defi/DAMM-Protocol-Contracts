// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IRouterWhitelistRegistry} from "@src/interfaces/IRouterWhitelistRegistry.sol";
import {IMulticallerWithSender} from "@src/interfaces/external/IMulticallerWithSender.sol";

interface IVaultRouterModule {
    error InvalidRouter();
    error OnlyOperator();
    error onlyOwnerVault();
    error NotDAMMVault();
    error TradingSuspended();
    error ModulePaused();

    event SetOperator(address indexed vault, address operator, bool enabled);
    event SuspendTrading(address vault);
    event ResumeTrading(address vault);

    function execute(address vault, address target, uint256 value, bytes calldata data)
        external
        returns (bytes memory);

    function executeMulticall(
        address vault,
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values
    ) external returns (bytes[] memory);

    function tradingSuspended(address vault) external view returns (bool);

    function suspendTrading() external;

    function resumeTrading() external;

    function setOperator(address operator, bool enabled) external;

    function operators(bytes32 operatorPointer) external view returns (bool);
}
