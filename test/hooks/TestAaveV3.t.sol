// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {HookRegistry} from "@src/modules/trading/HookRegistry.sol";
import {TradingModule} from "@src/modules/trading/TradingModule.sol";
import {SafeUtils, SafeTransaction} from "@test/utils/SafeUtils.sol";
import "@src/hooks/AaveV3Hooks.sol";
import {HookConfig} from "@src/modules/trading/Hooks.sol";
import {BaseAaveV3} from "@test/forked/BaseAaveV3.sol";
import {TokenMinter} from "@test/forked/TokenMinter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {console2} from "@forge-std/Test.sol";
import "@src/modules/trading/Structs.sol";

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
            deployContract(
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
                abi.encodePacked(
                    type(AaveV3Hooks).creationCode, abi.encode(address(fund), address(aaveV3Pool))
                )
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
        vm.stopPrank();

        mintUSDC(address(fund), BIG_NUMBER);
    }

    modifier withAllowance(IERC20 token) {
        vm.startPrank(address(fund));
        token.approve(address(aaveV3Pool), type(uint256).max);
        vm.stopPrank();
        _;
    }

    modifier enableAsset(address asset) {
        vm.startPrank(address(fund));
        aaveV3Hooks.enableAsset(asset);
        vm.stopPrank();
        _;
    }

    function test_supply() public withAllowance(USDC) enableAsset(address(ARB_USDC)) {
        assertEq(aUSDC.balanceOf(address(fund)), 0);

        Transaction[] memory calls = new Transaction[](1);

        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.supply.selector,
            data: abi.encode(ARB_USDC, 1000, address(fund), uint16(0)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        tradingModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 1000);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER - 1000);
    }

    function test_cannot_supply_unauthorized_asset() public withAllowance(USDT) {
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.supply.selector,
            data: abi.encode(address(USDC), 1000, address(fund), uint16(0)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(AaveV3Hooks.OnlyWhitelistedTokens.selector);
        tradingModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER);
    }

    function test_withdraw() public withAllowance(USDC) enableAsset(address(ARB_USDC)) {
        assertEq(aUSDC.balanceOf(address(fund)), 0);

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.supply.selector,
            data: abi.encode(ARB_USDC, 1000, address(fund), uint16(0)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        tradingModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 1000);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER - 1000);

        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.withdraw.selector,
            data: abi.encode(ARB_USDC, 1000, address(fund)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        tradingModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER);
    }

    function test_cannot_withdraw_unauthorized_asset() public withAllowance(USDC) {
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.withdraw.selector,
            data: abi.encode(address(USDC), 1000, address(fund)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(AaveV3Hooks.OnlyWhitelistedTokens.selector);
        tradingModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER);
    }

    function test_enable_disable_asset() public {
        bytes memory transaction =
            abi.encodeWithSelector(aaveV3Hooks.enableAsset.selector, address(ARB_USDC));

        bool success = fund.executeTrx(
            fundAdminPK,
            SafeTransaction({
                value: 0,
                target: address(aaveV3Hooks),
                operation: Enum.Operation.Call,
                transaction: transaction
            })
        );

        assertTrue(success, "Failed to enable asset");
        assertTrue(aaveV3Hooks.assetWhitelist(address(ARB_USDC)), "Asset not whitelisted");

        transaction = abi.encodeWithSelector(aaveV3Hooks.disableAsset.selector, address(ARB_USDC));

        success = fund.executeTrx(
            fundAdminPK,
            SafeTransaction({
                value: 0,
                target: address(aaveV3Hooks),
                operation: Enum.Operation.Call,
                transaction: transaction
            })
        );

        assertTrue(success, "Failed to disable asset");
        assertTrue(!aaveV3Hooks.assetWhitelist(address(ARB_USDC)), "Asset still whitelisted");
    }

    function test_only_fund_can_enable_asset(address attacker) public {
        vm.assume(attacker != address(fund));

        vm.expectRevert(AaveV3Hooks.OnlyFund.selector);
        vm.prank(attacker);
        aaveV3Hooks.enableAsset(address(ARB_USDC));
    }
}
