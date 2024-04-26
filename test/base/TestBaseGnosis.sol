// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.25;

import {Test} from "@forge-std/Test.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-contracts/proxies/SafeProxy.sol";
import {TokenCallbackHandler} from "@safe-contracts/handler/TokenCallbackHandler.sol";
import {MultiSend} from "@safe-contracts/libraries/MultiSend.sol";
import {CreateCall} from "@safe-contracts/libraries/CreateCall.sol";

abstract contract TestBaseGnosis is Test {
    MultiSend internal multiSend;
    SafeL2 internal safeSingleton;
    SafeProxyFactory internal safeProxyFactory;
    TokenCallbackHandler internal tokenCallbackHandler;
    CreateCall internal createCall;
    uint256 internal safeSaltNonce;

    function setUp() public virtual {
        multiSend = new MultiSend();
        vm.label(address(multiSend), "MultiSend");

        safeSingleton = new SafeL2();
        vm.label(address(safeSingleton), "SafeSingleton");

        safeProxyFactory = new SafeProxyFactory();
        vm.label(address(safeProxyFactory), "SafeProxyFactory");

        tokenCallbackHandler = new TokenCallbackHandler();
        vm.label(address(tokenCallbackHandler), "TokenCallbackHandler");

        createCall = new CreateCall();
        vm.label(address(createCall), "CreateCall");
    }

    function deploySafe(address[] memory admins, uint256 threshold) internal returns (SafeL2) {
        // create gnosis safe initializer payload
        bytes memory initializerPayload = abi.encodeCall(
            Safe.setup,
            (
                admins, // fund admins
                threshold, // multisig signer threshold
                address(0), // to
                "", // data
                address(tokenCallbackHandler), // fallback manager
                address(0), // payment token
                0, // payment amount
                payable(address(0)) // payment receiver
            )
        );

        address payable safe = payable(
            address(
                safeProxyFactory.createProxyWithNonce(address(safeSingleton), initializerPayload, 1)
            )
        );

        return SafeL2(safe);
    }
}
