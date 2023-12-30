// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {SafeProxyFactory} from "@safe-contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-contracts/proxies/SafeProxy.sol";
import {ISafe} from "@src/interfaces/external/ISafe.sol";
import {GnosisSafeModule} from "@src/base/GnosisSafeModule.sol";
import {BaseMulticallerWithSender} from "@test/base/BaseMulticallerWithSender.sol";
import {RouterWhitelistRegistry} from "@src/base/RouterWhitelistRegistry.sol";

abstract contract BaseVault is BaseMulticallerWithSender {
    SafeL2 internal safeSingleton;
    SafeProxyFactory internal safeProxyFactory;
    uint256 internal safeSaltNonce;

    RouterWhitelistRegistry public routerWhitelistRegistry;
    GnosisSafeModule public dammModule;

    address public vaultOwner;
    address public vault;

    function setUp() public virtual override(BaseMulticallerWithSender) {
        super.setUp();

        safeSingleton = new SafeL2();
        vm.label(address(safeSingleton), "SafeSingleton");

        safeProxyFactory = new SafeProxyFactory();
        vm.label(address(safeProxyFactory), "SafeProxyFactory");

        routerWhitelistRegistry = new RouterWhitelistRegistry();
        vm.label(address(routerWhitelistRegistry), "RouterWhitelistRegistry");

        dammModule =
            new GnosisSafeModule(address(this), address(routerWhitelistRegistry), address(multicallerWithSender));
        vm.label(address(dammModule), "SafeModule");

        vaultOwner = makeAddr("VaultOwner");

        address[] memory _owners = new address[](1);
        _owners[0] = vaultOwner;

        bytes memory data = abi.encodeWithSelector(this.enableModuleCallback.selector, (address(dammModule)));

        bytes memory initializerPayload = abi.encodeCall(
            ISafe.setup, (_owners, 1, address(this), data, address(0), address(0), 0, payable(address(0)))
        );

        vault = address(
            safeProxyFactory.createProxyWithNonce(
                address(safeSingleton),
                initializerPayload,
                uint256(keccak256(abi.encode(safeSaltNonce++, block.chainid)))
            )
        );

        vm.label(vault, "Vault");

        assertTrue(ISafe(vault).isModuleEnabled(address(dammModule)), "DAMM module not enabled");
    }

    /// @notice the safe delegatescall to this function upon deployment
    function enableModuleCallback(address _module) external {
        ISafe(address(this)).enableModule(_module);
    }
}
