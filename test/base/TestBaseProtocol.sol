// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";

import "@src/base/ProtocolAccessController.sol";
import "@src/base/ProtocolAddressRegistry.sol";
import "@src/base/ProtocolState.sol";
import "@src/base/RouterWhitelistRegistry.sol";
import "@src/base/TokenWhitelistRegistry.sol";
import "@src/base/VaultRouterModule.sol";
import "@src/VaultFactory.sol";
import "@src/base/VaultGuard.sol";

import {MulticallerEtcher} from "@vec-multicaller/MulticallerEtcher.sol";
import {MulticallerWithSender} from "@vec-multicaller/MulticallerWithSender.sol";
import "@src/interfaces/external/IMulticallerWithSender.sol";

import "@test/base/TestBaseGnosis.sol";

abstract contract TestBaseProtocol is Test, TestBaseGnosis {
    address internal owner;

    IProtocolAccessController internal protocolAccessController;
    IProtocolAddressRegistry internal protocolAddressRegistry;

    IProtocolState internal protocolState;
    IRouterWhitelistRegistry internal routerWhitelistRegistry;
    ITokenWhitelistRegistry internal tokenWhitelistRegistry;
    IMulticallerWithSender internal multicallerWithSender;
    IVaultFactory internal vaultFactory;
    IVaultRouterModule internal dammModule;
    IVaultGuard internal dammGuard;

    function setUp() public virtual override(TestBaseGnosis) {
        super.setUp();

        owner = makeAddr("Owner");

        vm.startPrank(owner, owner);
        protocolAccessController = IProtocolAccessController(address(new ProtocolAccessController(owner)));
        protocolAddressRegistry =
            IProtocolAddressRegistry(address(new ProtocolAddressRegistry(address(protocolAccessController))));

        multicallerWithSender = IMulticallerWithSender(address(MulticallerEtcher.multicallerWithSender()));

        protocolState = IProtocolState(address(new ProtocolState(protocolAddressRegistry)));
        routerWhitelistRegistry =
            IRouterWhitelistRegistry(address(new RouterWhitelistRegistry(protocolAddressRegistry)));
        tokenWhitelistRegistry = ITokenWhitelistRegistry(address(new TokenWhitelistRegistry(protocolAddressRegistry)));

        vaultFactory = IVaultFactory(
            address(
                new VaultFactory(
                    protocolAddressRegistry,
                    address(safeProxyFactory),
                    address(tokenCallbackHandler),
                    address(safeSingleton)
                )
            )
        );

        dammModule = IVaultRouterModule(address(new VaultRouterModule(protocolAddressRegistry)));
        dammGuard = IVaultGuard(address(new VaultGuard(protocolAddressRegistry)));

        protocolAddressRegistry.setProtocolState(address(protocolState));
        protocolAddressRegistry.setRouterWhitelistRegistry(address(routerWhitelistRegistry));
        protocolAddressRegistry.setTokenWhitelistRegistry(address(tokenWhitelistRegistry));
        protocolAddressRegistry.setMulticallerWithSender(address(multicallerWithSender));
        protocolAddressRegistry.setVaultFactory(address(vaultFactory));
        protocolAddressRegistry.setDAMMGnosisModule(address(dammModule));
        protocolAddressRegistry.setVaultGuard(address(dammGuard));

        vm.stopPrank();

        vm.label(address(protocolAccessController), "ProtocolAccessController");
        vm.label(address(protocolAddressRegistry), "ProtocolAddressRegistry");
        vm.label(address(protocolState), "ProtocolState");
        vm.label(address(routerWhitelistRegistry), "RouterWhitelistRegistry");
        vm.label(address(tokenWhitelistRegistry), "TokenWhitelistRegistry");
        vm.label(address(multicallerWithSender), "MulticallerWithSender");
        vm.label(address(vaultFactory), "VaultFactory");
        vm.label(address(dammModule), "VaultRouterModule");
        vm.label(address(dammGuard), "DAMMGuard");
    }

    function deployVault(address _owner) internal returns (address vault) {
        address[] memory owners = new address[](1);
        owners[0] = _owner;

        vault = vaultFactory.deployDAMMVault(owners, 1);
        vm.label(vault, "DAMMVault");
    }
}
