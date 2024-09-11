// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";

import "@test/forked/BaseUniswapV3.sol";
import "@test/base/TestBaseFund.sol";
import "@test/base/TestBaseProtocol.sol";
import "@safe-contracts/SafeL2.sol";
import "@safe-contracts/Safe.sol";
import "@src/modules/transact/HookRegistry.sol";
import "@src/modules/transact/TransactionModule.sol";
import "@test/forked/TokenMinter.sol";
import "@src/hooks/uniswapV3/UniswapV3Hooks.sol";
import {HookConfig} from "@src/modules/transact/Hooks.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import "@src/modules/transact/Structs.sol";
import {POSITION_OPENER_ROLE, POSITION_CLOSER_ROLE} from "@src/libs/Constants.sol";

contract TestUniswapV3 is TestBaseFund, TestBaseProtocol, BaseUniswapV3, TokenMinter {
    uint256 constant BIG_NUMBER = 10 ** 12;

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    HookRegistry internal hookRegistry;
    TransactionModule internal transactionModule;
    UniswapV3Hooks internal uniswapV3Hooks;

    uint176 nextPositionId;

    address internal operator;

    uint256 internal arbitrumFork;

    function setUp() public override(BaseUniswapV3, TokenMinter, TestBaseFund, TestBaseProtocol) {
        arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));

        vm.selectFork(arbitrumFork);
        assertEq(vm.activeFork(), arbitrumFork);

        BaseUniswapV3.setUp();
        TestBaseFund.setUp();
        TestBaseProtocol.setUp();
        TokenMinter.setUp();

        operator = makeAddr("Operator");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 1);
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

        uniswapV3Hooks = UniswapV3Hooks(
            deployModuleWithRoles(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("uniswapV3Hooks"),
                0,
                abi.encodePacked(
                    type(UniswapV3Hooks).creationCode,
                    abi.encode(
                        address(fund), UNI_V3_POSITION_MANAGER_ADDRESS, UNI_V3_SWAP_ROUTER_ADDRESS
                    )
                ),
                POSITION_OPENER_ROLE | POSITION_CLOSER_ROLE
            )
        );

        vm.label(address(uniswapV3Hooks), "UniswapV3Hooks");

        vm.startPrank(address(fund));
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: UNI_V3_POSITION_MANAGER_ADDRESS,
                beforeTrxHook: address(uniswapV3Hooks),
                afterTrxHook: address(uniswapV3Hooks),
                operation: 0,
                targetSelector: uniswapPositionManager.mint.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: UNI_V3_POSITION_MANAGER_ADDRESS,
                beforeTrxHook: address(uniswapV3Hooks),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: uniswapPositionManager.increaseLiquidity.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: UNI_V3_POSITION_MANAGER_ADDRESS,
                beforeTrxHook: address(uniswapV3Hooks),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: uniswapPositionManager.decreaseLiquidity.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: UNI_V3_POSITION_MANAGER_ADDRESS,
                beforeTrxHook: address(uniswapV3Hooks),
                afterTrxHook: address(uniswapV3Hooks),
                operation: 0,
                targetSelector: uniswapPositionManager.collect.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: UNI_V3_SWAP_ROUTER_ADDRESS,
                beforeTrxHook: address(uniswapV3Hooks),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: uniswapRouter.exactInputSingle.selector
            })
        );
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: UNI_V3_SWAP_ROUTER_ADDRESS,
                beforeTrxHook: address(uniswapV3Hooks),
                afterTrxHook: address(0),
                operation: 0,
                targetSelector: uniswapRouter.exactOutputSingle.selector
            })
        );
        vm.stopPrank();

        mintUSDC(address(fund), BIG_NUMBER);
        mintUSDCe(address(fund), BIG_NUMBER);

        nextPositionId = _getNextPositionId();
    }

    modifier approvePositionManagerAllowance(address approver) {
        vm.startPrank(address(approver));
        USDC.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        vm.stopPrank();
        _;
    }

    modifier approveSwapRouterAllowance(address approver) {
        vm.startPrank(address(approver));
        USDC.approve(UNI_V3_SWAP_ROUTER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_SWAP_ROUTER_ADDRESS, type(uint256).max);
        vm.stopPrank();
        _;
    }

    modifier enableAsset(address asset) {
        vm.startPrank(address(fund));
        uniswapV3Hooks.enableAsset(asset);
        vm.stopPrank();
        _;
    }

    function _getNextPositionId() private view returns (uint176) {
        /// @dev forge inspect ./lib/v3-periphery/contracts/NonfungiblePositionManager.sol:NonfungiblePositionManager storage-layout
        return uint176(uint256(vm.load(UNI_V3_POSITION_MANAGER_ADDRESS, bytes32(uint256(13)))));
    }

    function _mint_call() private view returns (Transaction memory trx) {
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
            .MintParams({
            token0: ARB_USDC,
            token1: ARB_USDCe,
            fee: 500,
            tickLower: 0,
            tickUpper: 500,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(fund),
            deadline: block.timestamp + 100
        });

        trx = Transaction({
            target: address(uniswapPositionManager),
            value: 0,
            targetSelector: uniswapPositionManager.mint.selector,
            data: abi.encode(mintParams),
            operation: uint8(Enum.Operation.Call)
        });
    }

    function _decrease_liquidity_call(uint176 positionId, uint128 liq)
        private
        view
        returns (Transaction memory trx)
    {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: positionId,
            liquidity: liq,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 100
        });

        trx = Transaction({
            target: address(uniswapPositionManager),
            value: 0,
            targetSelector: uniswapPositionManager.decreaseLiquidity.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });
    }

    function _increase_liquidity_call(uint176 positionId)
        private
        view
        returns (Transaction memory trx)
    {
        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
        INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: positionId,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 100
        });

        trx = Transaction({
            target: address(uniswapPositionManager),
            value: 0,
            targetSelector: uniswapPositionManager.increaseLiquidity.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });
    }

    function _collect_call(uint176 positionId) private view returns (Transaction memory trx) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager
            .CollectParams({
            tokenId: positionId,
            recipient: address(fund),
            amount0Max: 1000000,
            amount1Max: 1000000
        });

        trx = Transaction({
            target: address(uniswapPositionManager),
            value: 0,
            targetSelector: uniswapPositionManager.collect.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });
    }

    function _decrease_liquidity_call(uint176 positionId)
        private
        view
        returns (Transaction memory trx)
    {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: positionId,
            liquidity: 100,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 100
        });

        trx = Transaction({
            target: address(uniswapPositionManager),
            value: 0,
            targetSelector: uniswapPositionManager.decreaseLiquidity.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });
    }

    function test_mint_position()
        public
        approvePositionManagerAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        assertFalse(fund.hasOpenPositions());
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = _mint_call();

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(fund.hasOpenPositions());
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).balanceOf(address(fund)),
            1,
            "position not minted"
        );
        assertTrue(
            USDC.balanceOf(address(fund)) + USDCe.balanceOf(address(fund)) < BIG_NUMBER * 2,
            "no tokens spent"
        );
    }

    function test_cannot_mint_position_with_unauthorized_asset()
        public
        approvePositionManagerAllowance(address(fund))
    {
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
            .MintParams({
            token0: ARB_USDC,
            token1: ARB_USDCe,
            fee: 500,
            tickLower: 0,
            tickUpper: 500,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(fund),
            deadline: block.timestamp + 100
        });

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(uniswapPositionManager),
            value: 0,
            targetSelector: uniswapPositionManager.mint.selector,
            data: abi.encode(mintParams),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_OnlyWhitelistedTokens.selector);
        transactionModule.execute(calls);
    }

    function test_cannot_mint_position_to_other(address attacker)
        public
        approvePositionManagerAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
            .MintParams({
            token0: ARB_USDC,
            token1: ARB_USDCe,
            fee: 500,
            tickLower: 0,
            tickUpper: 500,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: attacker,
            deadline: block.timestamp + 100
        });

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(uniswapPositionManager),
            value: 0,
            targetSelector: uniswapPositionManager.mint.selector,
            data: abi.encode(mintParams),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_FundMustBeRecipient.selector);
        transactionModule.execute(calls);
    }

    function test_increase_liquidity()
        public
        approvePositionManagerAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        assertFalse(fund.hasOpenPositions());
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = _mint_call();

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(fund.hasOpenPositions());
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).balanceOf(address(fund)),
            1,
            "position not minted"
        );
        assertTrue(
            USDC.balanceOf(address(fund)) + USDCe.balanceOf(address(fund)) < BIG_NUMBER * 2,
            "no tokens spent"
        );

        uint256 token0Balance = USDC.balanceOf(address(fund));
        uint256 token1Balance = USDCe.balanceOf(address(fund));

        calls[0] = _increase_liquidity_call(nextPositionId);

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(fund.hasOpenPositions());
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).ownerOf(nextPositionId),
            address(fund),
            "not owned by fund"
        );
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).balanceOf(address(fund)),
            1,
            "position not minted"
        );
        assertTrue(
            USDC.balanceOf(address(fund)) + USDCe.balanceOf(address(fund))
                < token0Balance + token1Balance,
            "no tokens spent"
        );
    }

    function test_cannot_increase_liquidity_with_unauthorized_asset()
        public
        approvePositionManagerAllowance(address(fund))
    {
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
            .MintParams({
            token0: ARB_USDC,
            token1: ARB_USDCe,
            fee: 500,
            tickLower: 0,
            tickUpper: 500,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(fund),
            deadline: block.timestamp + 100
        });

        vm.prank(address(fund));
        uniswapPositionManager.mint(mintParams);

        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
        INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: nextPositionId,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 100
        });

        Transaction[] memory increaseLiquidityCalls = new Transaction[](1);
        increaseLiquidityCalls[0] = Transaction({
            target: address(uniswapPositionManager),
            value: 0,
            targetSelector: uniswapPositionManager.increaseLiquidity.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_OnlyWhitelistedTokens.selector);
        transactionModule.execute(increaseLiquidityCalls);
    }

    function test_cannot_increase_liquidity_of_position_that_is_not_owned_by_fund()
        public
        approvePositionManagerAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        address attacker = makeAddr("Attacker");
        vm.assume(attacker != address(fund));
        vm.assume(attacker != address(0));

        mintUSDC(attacker, BIG_NUMBER);
        mintUSDCe(attacker, BIG_NUMBER);

        vm.startPrank(attacker);
        USDC.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        uniswapPositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: ARB_USDC,
                token1: ARB_USDCe,
                fee: 500,
                tickLower: 0,
                tickUpper: 500,
                amount0Desired: 1000,
                amount1Desired: 1000,
                amount0Min: 0,
                amount1Min: 0,
                recipient: attacker,
                deadline: block.timestamp + 100
            })
        );
        vm.stopPrank();

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = _increase_liquidity_call(nextPositionId);

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_InvalidPosition.selector);
        transactionModule.execute(calls);
    }

    function test_decrease_liquidity()
        public
        approvePositionManagerAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        assertFalse(fund.hasOpenPositions());
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = _mint_call();

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(fund.hasOpenPositions());
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).balanceOf(address(fund)),
            1,
            "position not minted"
        );
        assertTrue(
            USDC.balanceOf(address(fund)) + USDCe.balanceOf(address(fund)) < BIG_NUMBER * 2,
            "no tokens spent"
        );

        (,,,,,,, uint128 liquidity,,,,) = uniswapPositionManager.positions(nextPositionId);

        calls[0] = _decrease_liquidity_call(nextPositionId);

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(fund.hasOpenPositions());
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).ownerOf(nextPositionId),
            address(fund),
            "not owned by fund"
        );
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).balanceOf(address(fund)),
            1,
            "position not minted"
        );

        (,,,,,,, uint128 finalLiq,,,,) = uniswapPositionManager.positions(nextPositionId);

        assertEq(finalLiq, liquidity - 100, "liquidity not decreased");
    }

    function test_cannot_decrease_liquidity_with_unauthorized_asset()
        public
        approvePositionManagerAllowance(address(fund))
    {
        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
            .MintParams({
            token0: ARB_USDC,
            token1: ARB_USDCe,
            fee: 500,
            tickLower: 0,
            tickUpper: 500,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(fund),
            deadline: block.timestamp + 100
        });

        vm.prank(address(fund));
        uniswapPositionManager.mint(mintParams);

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = _decrease_liquidity_call(nextPositionId);

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_OnlyWhitelistedTokens.selector);
        transactionModule.execute(calls);
    }

    function test_cannot_decrease_liquidity_of_position_that_is_not_owned_by_fund()
        public
        approvePositionManagerAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        address attacker = makeAddr("Attacker");
        vm.assume(attacker != address(fund));
        vm.assume(attacker != address(0));

        mintUSDC(attacker, BIG_NUMBER);
        mintUSDCe(attacker, BIG_NUMBER);

        vm.startPrank(attacker);
        USDC.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        uniswapPositionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: ARB_USDC,
                token1: ARB_USDCe,
                fee: 500,
                tickLower: 0,
                tickUpper: 500,
                amount0Desired: 1000,
                amount1Desired: 1000,
                amount0Min: 0,
                amount1Min: 0,
                recipient: attacker,
                deadline: block.timestamp + 100
            })
        );
        vm.stopPrank();

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = _decrease_liquidity_call(nextPositionId);

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_InvalidPosition.selector);
        transactionModule.execute(calls);
    }

    function test_collect_from_position()
        public
        approvePositionManagerAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        assertFalse(fund.hasOpenPositions());
        Transaction[] memory calls = new Transaction[](1);
        calls[0] = _mint_call();

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(fund.hasOpenPositions());

        uint256 token0Balance = USDC.balanceOf(address(fund));
        uint256 token1Balance = USDCe.balanceOf(address(fund));

        /// get position liquidity amount
        (,,,,,,, uint128 liquidity,,,,) = uniswapPositionManager.positions(nextPositionId);

        calls[0] = _decrease_liquidity_call(nextPositionId, liquidity);

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(fund.hasOpenPositions());

        calls[0] = _collect_call(nextPositionId);

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        (,,,,,,, uint128 finalLiquidity,,, uint128 finalToken0Owed, uint128 finalToken1Owed) =
            uniswapPositionManager.positions(nextPositionId);

        assertTrue(finalLiquidity == 0 && finalToken0Owed == 0 && finalToken1Owed == 0);

        assertFalse(fund.hasOpenPositions());
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).ownerOf(nextPositionId),
            address(fund),
            "not owned by fund"
        );
        assertEq(
            IERC721(UNI_V3_POSITION_MANAGER_ADDRESS).balanceOf(address(fund)),
            1,
            "position not minted"
        );
        assertTrue(
            USDC.balanceOf(address(fund)) + USDCe.balanceOf(address(fund)) < BIG_NUMBER * 2
                && USDC.balanceOf(address(fund)) + USDCe.balanceOf(address(fund))
                    > token0Balance + token1Balance,
            "no tokens returned"
        );
    }

    function test_cannot_collect_position_not_owned_by_fund() public {
        address attacker = makeAddr("Attacker");

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager
            .MintParams({
            token0: ARB_USDC,
            token1: ARB_USDCe,
            fee: 500,
            tickLower: 0,
            tickUpper: 500,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(attacker),
            deadline: block.timestamp + 100
        });

        mintUSDC(attacker, BIG_NUMBER);
        mintUSDCe(attacker, BIG_NUMBER);

        vm.startPrank(attacker);
        USDC.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        uniswapPositionManager.mint(mintParams);
        vm.stopPrank();

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = _collect_call(nextPositionId);

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_InvalidPosition.selector);
        transactionModule.execute(calls);
    }

    function test_exact_input_single_swap()
        public
        approveSwapRouterAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        uint256 usdcBalance = USDC.balanceOf(address(fund));
        uint256 bridgedBalance = USDCe.balanceOf(address(fund));

        IUniswapRouter.ExactInputSingleParams memory params = IUniswapRouter.ExactInputSingleParams({
            tokenIn: ARB_USDC,
            tokenOut: ARB_USDCe,
            fee: 500,
            recipient: address(fund),
            deadline: block.timestamp + 100,
            amountIn: 1000,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(uniswapRouter),
            value: 0,
            targetSelector: uniswapRouter.exactInputSingle.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(USDC.balanceOf(address(fund)) < usdcBalance, "no tokens spent");
        assertTrue(USDCe.balanceOf(address(fund)) > bridgedBalance, "no tokens recieved");
    }

    function test_cannot_exact_input_single_swap_unauthorized_asset()
        public
        approveSwapRouterAllowance(address(fund))
    {
        IUniswapRouter.ExactInputSingleParams memory params = IUniswapRouter.ExactInputSingleParams({
            tokenIn: ARB_USDC,
            tokenOut: ARB_USDCe,
            fee: 500,
            recipient: address(fund),
            deadline: block.timestamp + 100,
            amountIn: 1000,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(uniswapRouter),
            value: 0,
            targetSelector: uniswapRouter.exactInputSingle.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_OnlyWhitelistedTokens.selector);
        transactionModule.execute(calls);
    }

    function test_cannot_exact_input_single_swap_not_to_fund()
        public
        approveSwapRouterAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        IUniswapRouter.ExactInputSingleParams memory params = IUniswapRouter.ExactInputSingleParams({
            tokenIn: ARB_USDC,
            tokenOut: ARB_USDCe,
            fee: 500,
            recipient: makeAddr("Attacker"),
            deadline: block.timestamp + 100,
            amountIn: 1000,
            amountOutMinimum: 1,
            sqrtPriceLimitX96: 0
        });

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(uniswapRouter),
            value: 0,
            targetSelector: uniswapRouter.exactInputSingle.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_FundMustBeRecipient.selector);
        transactionModule.execute(calls);
    }

    function test_exact_output_single_swap()
        public
        approveSwapRouterAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        uint256 usdcBalance = USDC.balanceOf(address(fund));
        uint256 bridgedBalance = USDCe.balanceOf(address(fund));

        IUniswapRouter.ExactOutputSingleParams memory params = IUniswapRouter
            .ExactOutputSingleParams({
            tokenIn: ARB_USDC,
            tokenOut: ARB_USDCe,
            fee: 500,
            recipient: address(fund),
            deadline: block.timestamp + 100,
            amountOut: 1,
            amountInMaximum: 1000,
            sqrtPriceLimitX96: 0
        });

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(uniswapRouter),
            value: 0,
            targetSelector: uniswapRouter.exactOutputSingle.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        transactionModule.execute(calls);

        assertTrue(USDC.balanceOf(address(fund)) < usdcBalance, "no tokens spent");
        assertTrue(USDCe.balanceOf(address(fund)) > bridgedBalance, "no tokens recieved");
    }

    function test_cannot_exact_output_single_swap_unauthorized_asset()
        public
        approveSwapRouterAllowance(address(fund))
    {
        IUniswapRouter.ExactOutputSingleParams memory params = IUniswapRouter
            .ExactOutputSingleParams({
            tokenIn: ARB_USDC,
            tokenOut: ARB_USDCe,
            fee: 500,
            recipient: address(fund),
            deadline: block.timestamp + 100,
            amountOut: 1,
            amountInMaximum: 1000,
            sqrtPriceLimitX96: 0
        });

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(uniswapRouter),
            value: 0,
            targetSelector: uniswapRouter.exactOutputSingle.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_OnlyWhitelistedTokens.selector);
        transactionModule.execute(calls);
    }

    function test_cannot_exact_output_single_swap_not_to_fund()
        public
        approveSwapRouterAllowance(address(fund))
        enableAsset(ARB_USDC)
        enableAsset(ARB_USDCe)
    {
        IUniswapRouter.ExactOutputSingleParams memory params = IUniswapRouter
            .ExactOutputSingleParams({
            tokenIn: ARB_USDC,
            tokenOut: ARB_USDCe,
            fee: 500,
            recipient: makeAddr("Attacker"),
            deadline: block.timestamp + 100,
            amountOut: 1,
            amountInMaximum: 1000,
            sqrtPriceLimitX96: 0
        });

        Transaction[] memory calls = new Transaction[](1);
        calls[0] = Transaction({
            target: address(uniswapRouter),
            value: 0,
            targetSelector: uniswapRouter.exactOutputSingle.selector,
            data: abi.encode(params),
            operation: uint8(Enum.Operation.Call)
        });

        vm.prank(operator, operator);
        vm.expectRevert(UniswapV3Hooks_FundMustBeRecipient.selector);
        transactionModule.execute(calls);
    }

    function test_enable_disable_asset() public {
        vm.prank(address(fund));
        uniswapV3Hooks.enableAsset(address(ARB_USDC));

        assertTrue(uniswapV3Hooks.assetWhitelist(address(ARB_USDC)), "Asset not whitelisted");

        vm.prank(address(fund));
        uniswapV3Hooks.disableAsset(address(ARB_USDC));

        assertTrue(!uniswapV3Hooks.assetWhitelist(address(ARB_USDC)), "Asset still whitelisted");
    }

    function test_only_fund_can_enable_asset(address attacker) public {
        vm.assume(attacker != address(fund));

        vm.expectRevert(Errors.OnlyFund.selector);
        vm.prank(attacker);
        uniswapV3Hooks.enableAsset(address(ARB_USDC));
    }
}
