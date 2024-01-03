// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IMulticallerWithSender} from "@src/interfaces/external/IMulticallerWithSender.sol";
import {ISafe} from "@src/interfaces/external/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {IRouterWhitelistRegistry} from "@src/interfaces/IRouterWhitelistRegistry.sol";
import {IDAMMGnosisSafeModule} from "@src/interfaces/IDAMMGnosisSafeModule.sol";
import {ProtocolStateAccesor} from "@src/lib/ProtocolStateAccesor.sol";

contract DAMMGnosisSafeModule is ProtocolStateAccesor, IDAMMGnosisSafeModule {
    IMulticallerWithSender public immutable multicallerWithSender;
    IRouterWhitelistRegistry public immutable routerWhitelistRegistry;

    /// @notice keccak256(abi.encodePacked(vault, operator)) => bool
    mapping(bytes32 operatorPointer => bool enabled) public operators;

    /// @notice vaults can forcefully pause this module
    mapping(address vault => bool suspended) public tradingSuspended;

    constructor(address _protocolState, address _routerWhitelistRegistry, address _multicallerWithSender)
        ProtocolStateAccesor(_protocolState)
    {
        routerWhitelistRegistry = IRouterWhitelistRegistry(_routerWhitelistRegistry);
        multicallerWithSender = IMulticallerWithSender(_multicallerWithSender);
    }

    modifier onlyOperator(address vault, address operator) {
        if (!operators[_operatorPointer(vault, operator)]) revert OnlyOperator();
        _;
    }

    modifier tradingNotSuspended(address vault) {
        if (tradingSuspended[vault]) revert TradingSuspended();
        _;
    }

    function _operatorPointer(address vault, address operator) internal pure returns (bytes32) {
        return keccak256(abi.encode(vault, operator));
    }

    function setOperator(address operator, bool enabled) external {
        require(operator != address(0), "DAMMGnosisSafeModule: operator is zero address");
        if (paused() && enabled) revert ModulePaused();

        operators[_operatorPointer(msg.sender, operator)] = enabled;

        emit SetOperator(msg.sender, operator, enabled);
    }

    function suspendTrading() external {
        tradingSuspended[msg.sender] = true;

        emit ResumeTrading(msg.sender);
    }

    function resumeTrading() external {
        tradingSuspended[msg.sender] = false;

        emit SuspendTrading(msg.sender);
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
        notPaused
        tradingNotSuspended(vault)
        onlyOperator(vault, msg.sender)
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
    ) external override notPaused tradingNotSuspended(vault) onlyOperator(vault, msg.sender) returns (bytes[] memory) {
        uint256 length = targets.length;

        require(length == datas.length, "DAMMGnosisSafeModule: datas length mismatch");
        require(length == values.length, "DAMMGnosisSafeModule: values length mismatch");

        // sum up how much ETH the safe will need to send to the multicaller
        uint256 value;
        for (uint256 i = 0; i < length;) {
            _isValidTarget(vault, targets[i]);
            value += values[i];

            unchecked {
                ++i;
            }
        }

        bytes memory data =
            abi.encodeWithSelector(IMulticallerWithSender.aggregateWithSender.selector, targets, datas, values);

        /// @notice multicaller will revert if arrays are not of equal length
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
