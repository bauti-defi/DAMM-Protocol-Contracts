// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import "@test/base/TestBaseProtocol.sol";
import "@src/interfaces/external/ISafe.sol";
import {IStorageAccesible} from "@test/mocks/IStorageAccesible.sol";

contract TestVaultFactory is TestBaseProtocol {
    // keccak256("guard_manager.guard.address")
    bytes32 internal constant GUARD_STORAGE_SLOT =
        0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;

    address vaultOwner;

    function setUp() public override {
        super.setUp();

        vaultOwner = makeAddr("VaultOwner");
    }

    function test() public {
        address[] memory owners = new address[](1);
        owners[0] = vaultOwner;

        vm.prank(vaultOwner);
        address vault = vaultFactory.deployDAMMVault(owners, 1);

        assertEq(vaultFactory.getDeployedVaultNonce(vault), 1);
        assertEq(ISafe(vault).getOwners().length, 1);
        assertEq(ISafe(vault).getOwners()[0], vaultOwner);
        assertEq(ISafe(vault).getThreshold(), 1);
        assertEq(
            bytes32(IStorageAccesible(vault).getStorageAt(uint256(GUARD_STORAGE_SLOT), 32)) << 96,
            bytes32(bytes20(address(dammGuard)))
        );
        assertTrue(ISafe(vault).isModuleEnabled(address(dammModule)));

        vm.prank(vaultOwner);
        vault = vaultFactory.deployDAMMVault(owners, 1);

        assertEq(vaultFactory.getDeployedVaultNonce(vault), 2);
        assertEq(ISafe(vault).getOwners().length, 1);
        assertEq(ISafe(vault).getOwners()[0], vaultOwner);
        assertEq(ISafe(vault).getThreshold(), 1);
        assertEq(
            bytes32(IStorageAccesible(vault).getStorageAt(uint256(GUARD_STORAGE_SLOT), 32)) << 96,
            bytes32(bytes20(address(dammGuard)))
        );
        assertTrue(ISafe(vault).isModuleEnabled(address(dammModule)));
    }
}
