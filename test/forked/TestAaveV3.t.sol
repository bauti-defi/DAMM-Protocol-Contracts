// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {HookRegistry} from "@src/HookRegistry.sol";
import {TradingModule} from "@src/TradingModule.sol";
import {SafeUtils} from "@test/utils/SafeUtils.sol";
import {AaveV3Hooks} from "@src/hooks/AaveV3Hooks.sol";
import {HookConfig} from "@src/lib/Hooks.sol";
import {BaseAaveV3} from "@test/forked/BaseAaveV3.sol";
import {TokenMinter} from "@test/forked/TokenMinter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {console2} from "@forge-std/Test.sol";

contract TestAaveV3 is TestBaseGnosis, TestBaseProtocol, BaseAaveV3, TokenMinter {
    using SafeUtils for SafeL2;

    uint256 constant BIG_NUMBER = 10 ** 12;

    IERC20 internal constant aUSDC = IERC20(0x724dc807b04555b71ed48a6896b6F41593b8C637);

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    SafeL2 internal fund;
    HookRegistry internal hookRegistry;
    TradingModule internal tradingModule;
    AaveV3Hooks internal aaveV3Hooks;

    address internal operator;

    uint256 internal arbitrumFork;

    function setUp() public override(BaseAaveV3, TokenMinter, TestBaseGnosis, TestBaseProtocol) {
        arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));

        vm.selectFork(arbitrumFork);
        assertEq(vm.activeFork(), arbitrumFork);

        BaseAaveV3.setUp();
        TestBaseGnosis.setUp();
        TestBaseProtocol.setUp();
        TokenMinter.setUp();

        operator = makeAddr("Operator");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = deploySafe(admins, 1);
        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

        vm.deal(address(fund), 1000 ether);

        hookRegistry = HookRegistry(
            deployModule(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("hookRegistry"),
                0,
                abi.encodePacked(type(HookRegistry).creationCode, abi.encode(address(fund)))
            )
        );

        vm.label(address(hookRegistry), "HookRegistry");

        tradingModule = TradingModule(
            deployModule(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("tradingModule"),
                0,
                abi.encodePacked(
                    type(TradingModule).creationCode,
                    abi.encode(address(fund), address(hookRegistry))
                )
            )
        );
        vm.label(address(tradingModule), "TradingModule");

        assertEq(tradingModule.fund(), address(fund), "TradingModule fund not set");

        aaveV3Hooks = AaveV3Hooks(
            deployModule(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("aaveV3Hooks"),
                0,
                abi.encodePacked(type(AaveV3Hooks).creationCode, abi.encode(address(fund)))
            )
        );

        vm.label(address(aaveV3Hooks), "AaveV3Hooks");

        vm.startPrank(address(fund));
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3Hooks),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: aaveV3Pool.supply.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3Hooks),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: aaveV3Pool.withdraw.selector
            })
        );
        aaveV3Hooks.enableAsset(address(ARB_USDC));
        vm.stopPrank();

        mintUSDC(address(fund), BIG_NUMBER);
    }

    function test_supply() public {
        vm.startPrank(address(fund));
        USDC.approve(address(aaveV3Pool), type(uint256).max);
        vm.stopPrank();

        assertEq(aUSDC.balanceOf(address(fund)), 0);

        bytes memory supplyAaveCall = abi.encodeWithSelector(
            aaveV3Pool.supply.selector, ARB_USDC, 1000, address(fund), uint16(0)
        );

        bytes memory payload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(aaveV3Pool),
            uint256(0),
            supplyAaveCall.length,
            supplyAaveCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(payload);

        assertEq(aUSDC.balanceOf(address(fund)), 1000);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER - 1000);
    }

    function test_withdraw() public {
        vm.startPrank(address(fund));
        USDC.approve(address(aaveV3Pool), type(uint256).max);
        vm.stopPrank();

        assertEq(aUSDC.balanceOf(address(fund)), 0);

        bytes memory supplyAaveCall = abi.encodeWithSelector(
            aaveV3Pool.supply.selector, ARB_USDC, 1000, address(fund), uint16(0)
        );

        bytes memory payload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(aaveV3Pool),
            uint256(0),
            supplyAaveCall.length,
            supplyAaveCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(payload);

        assertEq(aUSDC.balanceOf(address(fund)), 1000);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER - 1000);

        bytes memory withdrawAaveCall =
            abi.encodeWithSelector(aaveV3Pool.withdraw.selector, ARB_USDC, 1000, address(fund));

        payload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(aaveV3Pool),
            uint256(0),
            withdrawAaveCall.length,
            withdrawAaveCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(payload);

        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER);
    }
}
