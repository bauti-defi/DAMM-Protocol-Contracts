// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IMulticallerWithSender} from "@src/interfaces/IMulticallerWithSender.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {IRouterWhitelistRegistry} from "@src/interfaces/IRouterWhitelistRegistry.sol";
import {IGnosisSafeModule} from "@src/interfaces/IGnosisSafeModule.sol";

contract GnosisSafeModule is IGnosisSafeModule {
    address public immutable owner;
    IMulticallerWithSender public immutable multicallerWithSender;
    IRouterWhitelistRegistry public immutable routerWhitelistRegistry;

    mapping(address operator => bool enabled) public operators;

    constructor(address _owner, address _routerWhitelistRegistry, address _multicallerWithSender) {
        owner = _owner;
        routerWhitelistRegistry = IRouterWhitelistRegistry(_routerWhitelistRegistry);
        multicallerWithSender = IMulticallerWithSender(_multicallerWithSender);
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyOperator() {
        if (!operators[msg.sender]) revert OnlyOperator();
        _;
    }

    function setOperator(address operator, bool enabled) external onlyOwner {
        operators[operator] = enabled;

        emit SetOperator(msg.sender, operator, enabled);
    }

    function _isValidTarget(address vault, address target) internal view {
        if (
            target == address(multicallerWithSender) || target == address(0) || target == address(this)
                || !routerWhitelistRegistry.isRouterWhitelisted(vault, target)
        ) revert InvalidRouter();
    }

    function execute(address vault, address target, uint256 value, bytes calldata data)
        external
        override
        onlyOperator
        returns (bytes memory)
    {
        _isValidTarget(vault, target);

        (bool success, bytes memory returnData) =
            ISafe(vault).execTransactionFromModuleReturnData(target, value, data, Enum.Operation.Call);
        if (!success) {
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577
            if (returnData.length < 68) revert();
            assembly {
                returnData := add(returnData, 0x04)
            }
            revert(abi.decode(returnData, (string)));
        }

        return returnData;
    }

    function executeMulticall(
        address vault,
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values
    ) external override onlyOperator returns (bytes[] memory) {
        // sum up how much ETH the safe will need to send to the multicaller
        uint256 value;
        for (uint256 i = 0; i < targets.length; ++i) {
            _isValidTarget(vault, targets[i]);
            value += values[i];
        }

        bytes memory data =
            abi.encodeWithSelector(IMulticallerWithSender.aggregateWithSender.selector, targets, datas, values);

        (bool success, bytes memory returnData) = ISafe(vault).execTransactionFromModuleReturnData(
            address(multicallerWithSender), value, data, Enum.Operation.Call
        );

        if (!success) {
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577
            if (returnData.length < 68) revert();
            assembly {
                returnData := add(returnData, 0x04)
            }
            revert(abi.decode(returnData, (string)));
        }

        return abi.decode(returnData, (bytes[]));
    }
}
