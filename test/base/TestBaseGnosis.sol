// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {SafeProxyFactory} from "@safe-contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-contracts/proxies/SafeProxy.sol";
import {TokenCallbackHandler} from "@safe-contracts/handler/TokenCallbackHandler.sol";

abstract contract TestBaseGnosis is Test {
    SafeL2 internal safeSingleton;
    SafeProxyFactory internal safeProxyFactory;
    TokenCallbackHandler internal tokenCallbackHandler;
    uint256 internal safeSaltNonce;

    function setUp() public virtual {
        safeSingleton = new SafeL2();
        vm.label(address(safeSingleton), "SafeSingleton");

        safeProxyFactory = new SafeProxyFactory();
        vm.label(address(safeProxyFactory), "SafeProxyFactory");

        tokenCallbackHandler = new TokenCallbackHandler();
        vm.label(address(tokenCallbackHandler), "TokenCallbackHandler");
    }
}
