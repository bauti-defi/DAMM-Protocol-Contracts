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
        uniswapV3Hooks.enableAsset(ARB_USDC);
        uniswapV3Hooks.enableAsset(ARB_USDCe);
        vm.stopPrank();

        mintUSDC(address(fund), BIG_NUMBER);
        mintUSDCe(address(fund), BIG_NUMBER);
    }

    function test_mint_position() public {
        vm.startPrank(address(fund));
        USDC.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        vm.stopPrank();

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager
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

        bytes memory mintCall = abi.encodeWithSelector(uniswapPositionManager.mint.selector, params);

        bytes memory payload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapPositionManager),
            uint256(0),
            mintCall.length,
            mintCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(payload);

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

    function test_increase_liquidity() public {
        vm.startPrank(address(fund));
        USDC.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        USDCe.approve(UNI_V3_POSITION_MANAGER_ADDRESS, type(uint256).max);
        vm.stopPrank();

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

        uint256 token0Balance = USDC.balanceOf(address(fund));
        uint256 token1Balance = USDCe.balanceOf(address(fund));

        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
        INonfungiblePositionManager.IncreaseLiquidityParams({
            tokenId: 0, // this is the wrong id!
            amount0Desired: 1000,
            amount1Desired: 1000,
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp + 100
        });

        bytes memory increaseLiquidityCall =
            abi.encodeWithSelector(uniswapPositionManager.increaseLiquidity.selector, params);

        bytes memory increaseLiquidityPayload = abi.encodePacked(
            uint8(Enum.Operation.Call),
            address(uniswapPositionManager),
            uint256(0),
            increaseLiquidityCall.length,
            increaseLiquidityCall
        );

        vm.prank(operator, operator);
        tradingModule.execute(increaseLiquidityPayload);

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
}
