// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestBaseFund, IFund} from "@test/base/TestBaseFund.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {HookRegistry} from "@src/modules/transact/HookRegistry.sol";
import {TransactionModule} from "@src/modules/transact/TransactionModule.sol";
import "@src/hooks/aaveV3/AaveV3CallValidator.sol";
import "@src/hooks/aaveV3/AaveV3PositionManager.sol";
import {HookConfig} from "@src/modules/transact/Hooks.sol";
import {BaseAaveV3} from "@test/forked/BaseAaveV3.sol";
import {TokenMinter} from "@test/forked/TokenMinter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {console2} from "@forge-std/Test.sol";
import "@src/modules/transact/Structs.sol";

contract TestAaveV3 is TestBaseFund, TestBaseProtocol, BaseAaveV3, TokenMinter {
    uint256 constant BIG_NUMBER = 10 ** 12;

    IERC20 internal constant aUSDC = IERC20(0x724dc807b04555b71ed48a6896b6F41593b8C637);

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    HookRegistry internal hookRegistry;
    TransactionModule internal transactionModule;
    AaveV3CallValidator internal aaveV3CallValidator;
    AaveV3PositionManager internal aaveV3PositionManager;
    address internal operator;

    uint256 internal arbitrumFork;

    function setUp() public override(BaseAaveV3, TokenMinter, TestBaseFund, TestBaseProtocol) {
        arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));

        vm.selectFork(arbitrumFork);
        assertEq(vm.activeFork(), arbitrumFork);

        BaseAaveV3.setUp();
        TestBaseFund.setUp();
        TestBaseProtocol.setUp();
        TokenMinter.setUp();

        operator = makeAddr("Operator");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 1, 1);
        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

        vm.deal(address(fund), 1000 ether);

        hookRegistry = HookRegistry(
            deployContract(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                address(createCall),
                bytes32("hookRegistry"),
                0,
                abi.encodePacked(type(HookRegistry).creationCode, abi.encode(address(fund)))
            )
        );

        vm.label(address(hookRegistry), "HookRegistry");

        transactionModule = TransactionModule(
            deployModule(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("transactionModule"),
                0,
                abi.encodePacked(
                    type(TransactionModule).creationCode,
                    abi.encode(address(fund), address(hookRegistry))
                )
            )
        );
        vm.label(address(transactionModule), "TransactionModule");

        assertEq(transactionModule.fund(), address(fund), "TransactionModule fund not set");

        aaveV3CallValidator = AaveV3CallValidator(
            deployModule(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("aaveV3CallValidator"),
                0,
                abi.encodePacked(
                    type(AaveV3CallValidator).creationCode,
                    abi.encode(address(fund), address(aaveV3Pool))
                )
            )
        );

        vm.label(address(aaveV3CallValidator), "AaveV3CallValidator");

        aaveV3PositionManager = AaveV3PositionManager(
            deployModuleWithRoles(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("aaveV3PositionManager"),
                0,
                abi.encodePacked(
                    type(AaveV3PositionManager).creationCode,
                    abi.encode(address(fund), address(aaveV3Pool))
                ),
                POSITION_OPENER_ROLE | POSITION_CLOSER_ROLE
            )
        );

        vm.label(address(aaveV3PositionManager), "AaveV3PositionManager");

        vm.startPrank(address(fund));
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3CallValidator),
                afterTrxHook: address(aaveV3PositionManager),
                operation: 0,
                targetSelector: aaveV3Pool.supply.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3CallValidator),
                afterTrxHook: address(aaveV3PositionManager),
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
        aaveV3CallValidator.enableAsset(asset);
        vm.stopPrank();
        _;
    }

    function test_supply() public withAllowance(USDC) enableAsset(address(ARB_USDC)) {
        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertFalse(fund.hasOpenPositions());

        Transaction[] memory calls = new Transaction[](1);

        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.supply.selector,
            data: abi.encode(ARB_USDC, 1000, address(fund), uint16(0)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 1000);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER - 1000);
        assertTrue(fund.hasOpenPositions());
    }

    function test_cannot_supply_to_recipient_that_is_not_fund()
        public
        withAllowance(USDC)
        enableAsset(address(ARB_USDC))
    {
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.supply.selector,
            data: abi.encode(address(ARB_USDC), 1000, makeAddr("Not Fund"), uint16(0)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(AaveV3CallValidator_FundMustBeRecipient.selector);
        transactionModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER);
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
        vm.expectRevert(AaveV3CallValidator_OnlyWhitelistedTokens.selector);
        transactionModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER);
    }

    function test_withdraw() public withAllowance(USDC) enableAsset(address(ARB_USDC)) {
        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertFalse(fund.hasOpenPositions());

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.supply.selector,
            data: abi.encode(ARB_USDC, 1000, address(fund), uint16(0)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(fund.hasOpenPositions());
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
        transactionModule.execute(calls);

        assertFalse(fund.hasOpenPositions());
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
        vm.expectRevert(AaveV3CallValidator_OnlyWhitelistedTokens.selector);
        transactionModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER);
    }

    function test_cannot_withdraw_to_recipient_that_is_not_fund()
        public
        withAllowance(USDC)
        enableAsset(address(ARB_USDC))
    {
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.withdraw.selector,
            data: abi.encode(address(ARB_USDC), 1000, makeAddr("Not Fund")),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(AaveV3CallValidator_FundMustBeRecipient.selector);
        transactionModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 0);
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER);
    }

    function test_enable_disable_asset() public {
        vm.prank(address(fund));
        aaveV3CallValidator.enableAsset(address(ARB_USDC));

        assertTrue(aaveV3CallValidator.assetWhitelist(address(ARB_USDC)), "Asset not whitelisted");

        vm.prank(address(fund));
        aaveV3CallValidator.disableAsset(address(ARB_USDC));

        assertTrue(
            !aaveV3CallValidator.assetWhitelist(address(ARB_USDC)), "Asset still whitelisted"
        );
    }

    function test_only_fund_can_enable_asset(address attacker) public {
        vm.assume(attacker != address(fund));

        vm.expectRevert(Errors.OnlyFund.selector);
        vm.prank(attacker);
        aaveV3CallValidator.enableAsset(address(ARB_USDC));
    }
}
