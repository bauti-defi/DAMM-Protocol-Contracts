// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IDeployContract {
    function deployContract(bytes32 salt, uint256 value, bytes memory creationCode)
        external
        returns (address contractAddress);

    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer)
        external
        pure
        returns (address addr);
}
