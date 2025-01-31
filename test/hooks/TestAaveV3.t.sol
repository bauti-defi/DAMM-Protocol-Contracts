// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Safe} from "@safe-contracts/Safe.sol";
import {HookRegistry} from "@src/modules/transact/HookRegistry.sol";
import {TransactionModule} from "@src/modules/transact/TransactionModule.sol";
import "@src/hooks/aaveV3/AaveV3CallValidator.sol";
import {HookConfig} from "@src/modules/transact/Hooks.sol";
import {BaseAaveV3} from "@test/forked/BaseAaveV3.sol";
import {TokenMinter} from "@test/forked/TokenMinter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {console2} from "@forge-std/Test.sol";
import "@src/modules/transact/Structs.sol";
import {UserConfiguration} from
    "@aave-v3-core/protocol/libraries/configuration/UserConfiguration.sol";

contract TestAaveV3 is TestBaseGnosis, TestBaseProtocol, BaseAaveV3, TokenMinter {
    uint256 constant BIG_NUMBER = 10 ** 12;

    IERC20 internal constant aUSDC = IERC20(0x724dc807b04555b71ed48a6896b6F41593b8C637);

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    ISafe internal fund;
    HookRegistry internal hookRegistry;
    TransactionModule internal transactionModule;
    AaveV3CallValidator internal aaveV3CallValidator;
    address internal operator;

    uint256 internal arbitrumFork;

    function setUp() public override(BaseAaveV3, TokenMinter, TestBaseProtocol, TestBaseGnosis) {
        arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));

        vm.selectFork(arbitrumFork);
        assertEq(vm.activeFork(), arbitrumFork);

        /// @notice fixed block to avoid flakiness
        vm.rollFork(218796378);

        BaseAaveV3.setUp();
        TestBaseGnosis.setUp();
        TestBaseProtocol.setUp();
        TokenMinter.setUp();

        operator = makeAddr("Operator");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = ISafe(address(deploySafe(admins, 1, 1)));
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

        vm.startPrank(address(fund));
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3CallValidator),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: aaveV3Pool.supply.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3CallValidator),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: aaveV3Pool.withdraw.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3CallValidator),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: aaveV3Pool.borrow.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3CallValidator),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: aaveV3Pool.repay.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: address(aaveV3Pool),
                beforeTrxHook: address(aaveV3CallValidator),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: aaveV3Pool.repayWithATokens.selector
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
        assertEq(aUSDC.balanceOf(address(fund)), 0, "aUSDC balance not 0");

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

        assertApproxEqAbs(aUSDC.balanceOf(address(fund)), 1000, 0.1e18, "aUSDC balance not ~1000");
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER - 1000, "USDC balance not 999000");
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
        assertEq(aUSDC.balanceOf(address(fund)), 0, "aUSDC balance not 0");

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

        assertApproxEqAbs(aUSDC.balanceOf(address(fund)), 1000, 0.1e18, "aUSDC balance not 1000");
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER - 1000, "USDC balance not 999000");

        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.withdraw.selector,
            data: abi.encode(ARB_USDC, 1000, address(fund)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertEq(aUSDC.balanceOf(address(fund)), 0, "aUSDC balance not 0");
        assertEq(USDC.balanceOf(address(fund)), BIG_NUMBER, "USDC balance not 1000000");
    }

    function test_supply_borrow_repay() public withAllowance(USDC) enableAsset(address(ARB_USDC)) {
        assertEq(aUSDC.balanceOf(address(fund)), 0, "aUSDC balance not 0");

        Transaction[] memory calls = new Transaction[](3);

        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.supply.selector,
            data: abi.encode(ARB_USDC, 1000, address(fund), uint16(0)),
            operation: uint8(Enum.Operation.Call)
        });
        calls[1] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.borrow.selector,
            data: abi.encode(ARB_USDC, 10, 2, uint16(0), address(fund)),
            operation: uint8(Enum.Operation.Call)
        });
        calls[2] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.borrow.selector,
            data: abi.encode(ARB_USDC, 10, 2, uint16(0), address(fund)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        /// partial repay
        calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.repay.selector,
            data: abi.encode(ARB_USDC, 10, 2, address(fund)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(
            UserConfiguration.isBorrowingAny(aaveV3Pool.getUserConfiguration(address(fund))),
            "fund is not borrowing"
        );

        /// full repay
        calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.repay.selector,
            data: abi.encode(ARB_USDC, type(uint256).max, 2, address(fund)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertFalse(
            UserConfiguration.isBorrowingAny(aaveV3Pool.getUserConfiguration(address(fund))),
            "fund is borrowing"
        );
    }

    function test_supply_borrow_repay_with_atoken()
        public
        withAllowance(USDC)
        enableAsset(address(ARB_USDC))
    {
        assertEq(aUSDC.balanceOf(address(fund)), 0);

        Transaction[] memory calls = new Transaction[](2);

        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.supply.selector,
            data: abi.encode(ARB_USDC, 1000, address(fund), uint16(0)),
            operation: uint8(Enum.Operation.Call)
        });
        calls[1] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.borrow.selector,
            data: abi.encode(ARB_USDC, 50, 2, uint16(0), address(fund)),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        /// full repay with atoken
        calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(aaveV3Pool),
            value: 0,
            targetSelector: aaveV3Pool.repayWithATokens.selector,
            data: abi.encode(ARB_USDC, type(uint256).max, 2),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);
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
