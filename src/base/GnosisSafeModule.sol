// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IMulticallerWithSender} from "@src/interfaces/IMulticallerWithSender.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";

contract GnosisSafeModule {
    address public immutable owner;
    IMulticallerWithSender public immutable multicallerWithSender;
    mapping(address operator => bool enabled) public operators;
    mapping(address routers => bool enabled) public routers;

    constructor(address _owner, address _multicallerWithSender) {
        owner = _owner;
        multicallerWithSender = IMulticallerWithSender(_multicallerWithSender);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "GnosisSafeModule: only owner");
        _;
    }

    modifier onlyOperator() {
        require(operators[msg.sender], "GnosisSafeModule: only operator");
        _;
    }

    function setOperator(address operator, bool enabled) external onlyOwner {
        operators[operator] = enabled;
    }

    function setRouter(address router, bool enabled) external onlyOwner {
        require(
            router != address(multicallerWithSender) && router != address(0) && router != address(this),
            "GnosisSafeModule: invalid router"
        );
        routers[router] = enabled;
    }

    function execute(address vault, address target, uint256 value, bytes calldata data)
        external
        onlyOperator
        returns (bytes memory)
    {
        require(routers[target], "GnosisSafeModule: target is not router");

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
    ) external payable onlyOperator returns (bytes[] memory) {
        // sum up how much ETH the safe will need to send to the multicaller
        uint256 value;
        for (uint256 i = 0; i < targets.length; ++i) {
            require(routers[targets[i]], "GnosisSafeModule: target is not router");
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
