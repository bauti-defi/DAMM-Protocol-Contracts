// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test} from "@forge-std/Test.sol";

import "@test/forked/BaseUniswapV3.sol";
import "@test/base/TestBaseGnosis.sol";
import "@test/base/TestBaseProtocol.sol";
import "@safe-contracts/SafeL2.sol";
import "@safe-contracts/Safe.sol";
import "@src/HookRegistry.sol";
import "@src/TradingModule.sol";
import "@test/utils/SafeUtils.sol";
import "@test/forked/TokenMinter.sol";
import "@src/hooks/UniswapV3Hooks.sol";
import {HookConfig} from "@src/lib/Hooks.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";

contract TestUniswapV3 is TestBaseGnosis, TestBaseProtocol, BaseUniswapV3, TokenMinter {
    using SafeUtils for SafeL2;

    uint256 constant BIG_NUMBER = 10 ** 12;

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    SafeL2 internal fund;
    HookRegistry internal hookRegistry;
    TradingModule internal tradingModule;
    UniswapV3Hooks internal uniswapV3Hooks;

    uint176 nextPositionId;

    address internal operator;

    uint256 internal arbitrumFork;

    function setUp()
        public
        override(BaseUniswapV3, TokenMinter, TestBaseGnosis, TestBaseProtocol)
    {
        arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));

        vm.selectFork(arbitrumFork);
        assertEq(vm.activeFork(), arbitrumFork);

        BaseUniswapV3.setUp();
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

        uniswapV3Hooks = UniswapV3Hooks(
            deployModule(
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
                )
            )
        );

        vm.label(address(uniswapV3Hooks), "UniswapV3Hooks");

        vm.startPrank(address(fund));
        hookRegistry.setHooks(
            HookConfig({
                operator: operator,
                target: UNI_V3_POSITION_MANAGER_ADDRESS,
                beforeTrxHook: address(uniswapV3Hooks),
                afterTrxHook: address(0),
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
                afterTrxHook: address(0),
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
        uniswapV3Hooks.enableAsset(ARB_USDC);
        uniswapV3Hooks.enableAsset(ARB_USDCe);
        vm.stopPrank();

        mintUSDC(address(fund), BIG_NUMBER);
        mintUSDCe(address(fund), BIG_NUMBER);

        nextPositionId = _getNextPositionId();
    }

    modifier approvePositionManagerAllowance() {
        vm.startPrank(address(fund));
        USDC.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        vm.stopPrank();
        _;
    }

    modifier approveSwapRouterAllowance() {
        vm.startPrank(address(fund));
        USDC.approve(UNI_V3_SWAP_ROUTER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_SWAP_ROUTER_ADDRESS, type(uint256).max);
        vm.stopPrank();
        _;
    }

    function _getNextPositionId() private view returns (uint176) {
        /// @dev forge inspect ./lib/v3-periphery/contracts/NonfungiblePositionManager.sol:NonfungiblePositionManager storage-layout
        return uint176(uint256(vm.load(UNI_V3_POSITION_MANAGER_ADDRESS, bytes32(uint256(13)))));
    }

    function _mint_call() private returns (bytes memory) {
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

        bytes memory mintCall =
            abi.encodeWithSelector(uniswapPositionManager.mint.selector, mintParams);

        return abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapPositionManager),
            uint256(0),
            mintCall.length,
            mintCall
        );
    }

    function _decrease_liquidity_call(uint176 positionId, uint128 liq)
        private
        returns (bytes memory)
    {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: positionId,
            liquidity: liq,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 100
        });

        bytes memory decreaseLiquidityCall =
            abi.encodeWithSelector(uniswapPositionManager.decreaseLiquidity.selector, params);

        return abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapPositionManager),
            uint256(0),
            decreaseLiquidityCall.length,
            decreaseLiquidityCall
        );
    }

    function _increase_liquidity_call(uint176 positionId) private returns (bytes memory) {
        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
        INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: positionId,
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 100
        });

        bytes memory increaseLiquidityCall =
            abi.encodeWithSelector(uniswapPositionManager.increaseLiquidity.selector, params);

        return abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapPositionManager),
            uint256(0),
            increaseLiquidityCall.length,
            increaseLiquidityCall
        );
    }

    function test_mint_position() public approvePositionManagerAllowance {
        vm.prank(operator, operator);
        tradingModule.execute(_mint_call());

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

    function test_increase_liquidity() public approvePositionManagerAllowance {
        vm.prank(operator, operator);
        tradingModule.execute(_mint_call());

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

        vm.prank(operator, operator);
        tradingModule.execute(_increase_liquidity_call(nextPositionId));

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

    function test_decrease_liquidity() public approvePositionManagerAllowance {
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

        bytes memory mintCall =
            abi.encodeWithSelector(uniswapPositionManager.mint.selector, mintParams);

        bytes memory mintPayload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapPositionManager),
            uint256(0),
            mintCall.length,
            mintCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(mintPayload);

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

        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
        INonfungiblePositionManager.DecreaseLiquidityParams({
            tokenId: nextPositionId,
            liquidity: 100,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 100
        });

        bytes memory decreaseLiquidityCall =
            abi.encodeWithSelector(uniswapPositionManager.decreaseLiquidity.selector, params);

        bytes memory decreaseLiquidityPayload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapPositionManager),
            uint256(0),
            decreaseLiquidityCall.length,
            decreaseLiquidityCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(decreaseLiquidityPayload);

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

    function test_collect_from_position() public approvePositionManagerAllowance {
        vm.prank(operator, operator);
        tradingModule.execute(_mint_call());

        uint256 token0Balance = USDC.balanceOf(address(fund));
        uint256 token1Balance = USDCe.balanceOf(address(fund));

        vm.prank(operator, operator);
        tradingModule.execute(_decrease_liquidity_call(nextPositionId, 100));

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager
            .CollectParams({
            tokenId: nextPositionId,
            recipient: address(fund),
            amount0Max: 1000,
            amount1Max: 1000
        });

        bytes memory collectCall =
            abi.encodeWithSelector(uniswapPositionManager.collect.selector, params);

        bytes memory collectPayload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapPositionManager),
            uint256(0),
            collectCall.length,
            collectCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(collectPayload);

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

    function test_exact_input_single_swap() public approveSwapRouterAllowance {
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

        bytes memory swapCall =
            abi.encodeWithSelector(uniswapRouter.exactInputSingle.selector, params);

        bytes memory swapPayload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapRouter),
            uint256(0),
            swapCall.length,
            swapCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(swapPayload);

        assertTrue(USDC.balanceOf(address(fund)) < usdcBalance, "no tokens spent");
        assertTrue(USDCe.balanceOf(address(fund)) > bridgedBalance, "no tokens recieved");
    }

    function test_exact_output_single_swap() public approveSwapRouterAllowance {
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

        bytes memory swapCall =
            abi.encodeWithSelector(uniswapRouter.exactOutputSingle.selector, params);

        bytes memory swapPayload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapRouter),
            uint256(0),
            swapCall.length,
            swapCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(swapPayload);

        assertTrue(USDC.balanceOf(address(fund)) < usdcBalance, "no tokens spent");
        assertTrue(USDCe.balanceOf(address(fund)) > bridgedBalance, "no tokens recieved");
    }
}
