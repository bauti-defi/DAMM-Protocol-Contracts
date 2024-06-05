// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISafe} from "@src/interfaces/ISafe.sol";
import {IModuleFactory} from "@src/interfaces/IModuleFactory.sol";

contract ModuleFactory is IModuleFactory {
    error DeploymentFailed();
    error ModuleSetupFailed();
    error InsufficientBalance();
    error EmptyBytecode();
    error OnlyDelegateCall();

    event ModuleDeployed(address safe, address module);

    address private immutable self;

    constructor() {
        self = address(this);
    }

    modifier isDelegateCall() {
        if (address(this) == self) revert OnlyDelegateCall();
        _;
    }

    function deployContract(bytes32 salt, uint256 value, bytes memory creationCode)
        external
        isDelegateCall
        returns (address contractAddress)
    {
        if (address(this).balance < value) revert InsufficientBalance();

        if (creationCode.length == 0) revert EmptyBytecode();

        // solhint-disable-next-line no-inline-assembly
        assembly {
            contractAddress := create2(value, add(0x20, creationCode), mload(creationCode), salt)
        }
        if (contractAddress == address(0)) revert DeploymentFailed();
    }

    /// deploys a module and adds module to safe.
    ///  @dev the safe must delegate call this function for the module to be added properly
    /// always be causious when using delegatecall!!
    function deployModule(bytes32 salt, uint256 value, bytes memory creationCode)
        external
        isDelegateCall
        returns (address module)
    {
        if (address(this).balance < value) revert InsufficientBalance();

        if (creationCode.length == 0) revert EmptyBytecode();

        // solhint-disable-next-line no-inline-assembly
        assembly {
            module := create2(value, add(0x20, creationCode), mload(creationCode), salt)
        }
        if (module == address(0)) revert DeploymentFailed();

        // callback: add module to the safe. msg.sender is this because of delegatecall
        ISafe(address(this)).enableModule(module);
        if (!ISafe(address(this)).isModuleEnabled(module)) revert ModuleSetupFailed();

        emit ModuleDeployed(address(this), module);
    }

    /**
     * @dev this code snippet is from OpenZeppelin's implementation, we thank them for this.
     * @dev Returns the address where a contract will be stored if deployed via {deploy} from a contract located at
     * `deployer`. If `deployer` is this contract's address, returns the same value as {computeAddress}.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer)
        external
        pure
        returns (address addr)
    {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40) // Get free memory pointer

            // |                   | ↓ ptr ...  ↓ ptr + 0x0B (start) ...  ↓ ptr + 0x20 ...  ↓ ptr + 0x40 ...   |
            // |-------------------|---------------------------------------------------------------------------|
            // | bytecodeHash      |                                                        CCCCCCCCCCCCC...CC |
            // | salt              |                                      BBBBBBBBBBBBB...BB                   |
            // | deployer          | 000000...0000AAAAAAAAAAAAAAAAAAA...AA                                     |
            // | 0xFF              |            FF                                                             |
            // |-------------------|---------------------------------------------------------------------------|
            // | memory            | 000000...00FFAAAAAAAAAAAAAAAAAAA...AABBBBBBBBBBBBB...BBCCCCCCCCCCCCC...CC |
            // | keccak(start, 85) |            ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑ |

            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer) // Right-aligned with 12 preceding garbage bytes
            let start := add(ptr, 0x0b) // The hashed data starts at the final garbage byte which we will set to 0xff
            mstore8(start, 0xff)
            addr := keccak256(start, 85)
        }
    }
}
