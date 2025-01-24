// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {FundFactory, IFundFactory} from "@src/core/FundFactory.sol";
import {TestBaseGnosis} from "./base/TestBaseGnosis.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {IFund} from "@src/interfaces/IFund.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializerPayload, uint256 nonce)
        external
        returns (address);
}

contract TestFallbackHandler {
    bool public called;

    function targetFunction() external returns (bool) {
        called = true;
        return true;
    }

    function reset() external {
        called = false;
    }
}

// keccak256("fallback_manager.handler.address")
bytes32 constant FALLBACK_HANDLER_STORAGE_SLOT =
    0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;

contract TestFundFactory is TestBaseGnosis {
    FundFactory internal fundFactory;

    function setUp() public override(TestBaseGnosis) {
        TestBaseGnosis.setUp();

        fundFactory = new FundFactory();
    }

    function test_deploy_fund() public {
        address[] memory admins = new address[](1);
        admins[0] = address(this);

        ISafe fund = ISafe(
            address(
                fundFactory.deployFund(
                    address(safeProxyFactory), address(safeSingleton), admins, 1, 1
                )
            )
        );

        assertTrue(address(fund) != address(0), "Fund should be deployed");
        assertTrue(fund.isOwner(address(this)), "This should be owner");
        assertEq(fund.getThreshold(), 1, "Threshold should be 1");
        assertEq(fund.nonce(), 0, "Nonce should be 0");
    }

    function test_convert_safe_to_fund() public {
        address mockFallbackHandler = makeAddr("MockFallbackHandler");

        address[] memory admins = new address[](1);
        admins[0] = address(this);

        /// create gnosis safe initializer payload
        bytes memory initializerPayload = abi.encodeWithSelector(
            ISafe.setup.selector,
            admins,
            1,
            address(0),
            "",
            mockFallbackHandler,
            address(0),
            0,
            payable(address(0))
        );

        ISafe safe = ISafe(
            address(
                safeProxyFactory.createProxyWithNonce(address(safeSingleton), initializerPayload, 0)
            )
        );

        assertTrue(address(safe) != address(0), "Safe should be deployed");
        assertTrue(safe.isOwner(address(this)), "This should be owner");
        assertEq(safe.getThreshold(), 1, "Threshold should be 1");
        assertEq(safe.nonce(), 0, "Nonce should be 0");

        bytes32 slot = vm.load(address(safe), FALLBACK_HANDLER_STORAGE_SLOT);
        assertEq(
            slot,
            bytes32(uint256(uint160(address(mockFallbackHandler)))),
            "Fallback handler should be safe"
        );

        address module = makeAddr("Module");

        vm.prank(address(safe));
        safe.enableModule(module);

        vm.prank(module);
        safe.execTransactionFromModule(
            address(fundFactory),
            0,
            abi.encodeWithSelector(IFundFactory.convertSafeToFund.selector),
            Enum.Operation.DelegateCall
        );

        IFund fund = IFund(address(safe));

        assertTrue(address(fund) != address(0), "Fund should be deployed");
        assertTrue(fund.isOwner(address(this)), "This should be owner");
        assertEq(fund.getThreshold(), 1, "Threshold should be 1");
        assertEq(fund.nonce(), 0, "Nonce should be 0");

        slot = vm.load(address(safe), FALLBACK_HANDLER_STORAGE_SLOT);
        assertNotEq(
            slot,
            bytes32(uint256(uint160(address(mockFallbackHandler)))),
            "Fallback handler should not be safe"
        );

        assertEq(fund.getChildFunds().length, 0, "Child funds should be 0");
        assertEq(
            fund.getFundLiquidationTimeSeries().length,
            0,
            "Fund liquidation time series should be 0"
        );
        assertEq(fund.getLatestLiquidationBlock(), -1, "Latest liquidation block should be -1");
    }
}
