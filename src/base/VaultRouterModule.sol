// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {IMulticallerWithSender} from "@src/interfaces/external/IMulticallerWithSender.sol";
import {ISafe} from "@src/interfaces/external/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {IRouterWhitelistRegistry} from "@src/interfaces/IRouterWhitelistRegistry.sol";
import {IVaultRouterModule} from "@src/interfaces/IVaultRouterModule.sol";
import {IProtocolState} from "@src/interfaces/IProtocolState.sol";
import {ReentrancyGuard} from "@openzeppelin-contracts/utils/ReentrancyGuard.sol";
import {IVaultFactory} from "@src/interfaces/IVaultFactory.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {SafeGet} from "@src/lib/SafeGet.sol";

contract VaultRouterModule is ReentrancyGuard, IVaultRouterModule {
    using SafeGet for address;

    IProtocolAddressRegistry private immutable ADDRESS_REGISTRY;

    /// @notice keccak256(abi.encodePacked(vault, operator)) => bool
    mapping(bytes32 operatorPointer => bool enabled) public operators;

    /// @notice vaults can forcefully pause this module
    mapping(address vault => bool suspended) public tradingSuspended;

    constructor(IProtocolAddressRegistry addressRegistry) {
        ADDRESS_REGISTRY = addressRegistry;
    }

    modifier onlyOperator(address vault, address operator) {
        if (!operators[_operatorPointer(vault, operator)]) revert OnlyOperator();
        _;
    }

    modifier onlyVault() {
        if (!IVaultFactory(ADDRESS_REGISTRY.getVaultFactory().orRevert()).isDAMMVault(msg.sender)) {
            revert NotDAMMVault();
        }
        _;
    }

    modifier canExecute(address vault) {
        if (!IVaultFactory(ADDRESS_REGISTRY.getVaultFactory().orRevert()).isDAMMVault(vault)) {
            revert NotDAMMVault();
        }
        if (tradingSuspended[vault]) revert TradingSuspended();
        _;
    }

    function _operatorPointer(address vault, address operator) internal pure returns (bytes32) {
        return keccak256(abi.encode(vault, operator));
    }

    function setOperator(address operator, bool enabled) external onlyVault {
        require(operator != address(0), "VaultRouterModule: operator is zero address");
        require(operator != msg.sender, "VaultRouterModule: operator is self");
        require(
            !IVaultFactory(ADDRESS_REGISTRY.getVaultFactory().orRevert()).isDAMMVault(operator),
            "VaultRouterModule: operator is vault"
        );
        require(
            !ADDRESS_REGISTRY.isRegistered(operator),
            "VaultRouterModule: operator is reserved address"
        );

        if (IProtocolState(ADDRESS_REGISTRY.getProtocolState().orRevert()).paused() && enabled) {
            revert ModulePaused();
        }

        operators[_operatorPointer(msg.sender, operator)] = enabled;

        emit SetOperator(msg.sender, operator, enabled);
    }

    function suspendTrading() external onlyVault {
        tradingSuspended[msg.sender] = true;

        emit ResumeTrading(msg.sender);
    }

    function resumeTrading() external onlyVault {
        if (IProtocolState(ADDRESS_REGISTRY.getProtocolState().orRevert()).paused()) {
            revert ModulePaused();
        }

        tradingSuspended[msg.sender] = false;

        emit SuspendTrading(msg.sender);
    }

    function _checkTargetIsValid(address vault, address target) internal view {
        if (
            target == address(0) || target == address(this) || vault == target
                || ADDRESS_REGISTRY.isRegistered(target)
                || !IRouterWhitelistRegistry(ADDRESS_REGISTRY.getRouterWhitelistRegistry().orRevert())
                    .isRouterWhitelisted(vault, target)
        ) revert InvalidRouter();
    }

    function execute(address vault, address target, uint256 value, bytes calldata data)
        external
        override
        nonReentrant
        canExecute(vault)
        onlyOperator(vault, msg.sender)
        returns (bytes memory)
    {
        IProtocolState(ADDRESS_REGISTRY.getProtocolState().orRevert()).requireNotStopped();

        _checkTargetIsValid(vault, target);

        (bool success, bytes memory returnData) = ISafe(vault).execTransactionFromModuleReturnData(
            target, value, data, Enum.Operation.Call
        );
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

    /// @dev Multicallers will revert if arrays are not of equal length
    /// @dev Multicaller will revert upon reentrancy
    function executeMulticall(
        address vault,
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values
    )
        external
        override
        canExecute(vault)
        onlyOperator(vault, msg.sender)
        returns (bytes[] memory)
    {
        IProtocolState(ADDRESS_REGISTRY.getProtocolState().orRevert()).requireNotStopped();

        uint256 length = targets.length;

        // sum up how much ETH the safe will need to send to the multicaller
        uint256 value;
        for (uint256 i = 0; i < length;) {
            _checkTargetIsValid(vault, targets[i]);
            value += values[i];

            unchecked {
                ++i;
            }
        }

        bytes memory data = abi.encodeWithSelector(
            IMulticallerWithSender.aggregateWithSender.selector, targets, datas, values
        );

        (bool success, bytes memory returnData) = ISafe(vault).execTransactionFromModuleReturnData(
            ADDRESS_REGISTRY.getMulticallerWithSender(), value, data, Enum.Operation.Call
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
