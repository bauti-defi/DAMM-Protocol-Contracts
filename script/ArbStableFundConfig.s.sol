// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {DeployConfigLoader} from "@script/DeployConfigLoader.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@src/ModuleFactory.sol";
import "@src/HookRegistry.sol";
import "@src/TradingModule.sol";
import "@safe-contracts/Safe.sol";
import "@src/hooks/UniswapV3Hooks.sol";
import "@src/hooks/AaveV3Hooks.sol";

contract ArbStableFundConfig is DeployConfigLoader {
    address payable public constant STABLE_FUND =
        payable(address(0x3a3B7991613E6433C0753D0B7c7251f92c490F40));
    address public constant FUND_ADMIN = address(0x5822B262EDdA82d2C6A436b598Ff96fA9AB894c4);
    address public constant MODULE_FACTORY = address(0xe30E57cf7D69cBdDD9713AAb109753b5fa1878A5);
    address public constant HOOK_REGISTRY = address(0xeD521af25787c472A0428FAED83f3edf627EFcE7);
    address public constant TRADING_MODULE = address(0x61e699f8f636917Cd9B2E4723756d5eF3257fd2c);
    address public constant UNISWAP_V3_HOOKS = address(0x09991D5958f4d72812Aec65aF8b78969223D4799);
    address public constant AAVE_V3_HOOKS = address(0x5dc3D4F83B4Cb9542689338079893Ca2b4B62411);

    // stablecoins deployed on arbitrum
    address constant ARB_USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant ARB_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant ARB_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    address constant OPERATOR = address(0x5ed25671f65d0ca26d79326BF571f8AeaF856f00);

    function setUp() public override {
        super.setUp();
    }

    function verify() public {
        HookRegistry hookRegistry = HookRegistry(HOOK_REGISTRY);

        bool defined = true;
        require(
            hookRegistry.getHooks(OPERATOR, chainConfig.aave.pool, 0, IPool.withdraw.selector)
                .defined == defined,
            "aave withdraw"
        );
        require(
            hookRegistry.getHooks(OPERATOR, chainConfig.aave.pool, 0, IPool.supply.selector).defined
                == defined,
            "aave supply"
        );

        require(
            hookRegistry.getHooks(
                OPERATOR,
                chainConfig.uniswap.positionManager,
                0,
                INonfungiblePositionManager.mint.selector
            ).defined == defined,
            "uniswap mint"
        );
        require(
            hookRegistry.getHooks(
                OPERATOR,
                chainConfig.uniswap.positionManager,
                0,
                INonfungiblePositionManager.collect.selector
            ).defined == defined,
            "uniswap collect"
        );
        require(
            hookRegistry.getHooks(
                OPERATOR,
                chainConfig.uniswap.positionManager,
                0,
                INonfungiblePositionManager.increaseLiquidity.selector
            ).defined == defined,
            "uniswap increaseLiquidity"
        );
        require(
            hookRegistry.getHooks(
                OPERATOR,
                chainConfig.uniswap.positionManager,
                0,
                INonfungiblePositionManager.decreaseLiquidity.selector
            ).defined == defined,
            "uniswap decreaseLiquidity"
        );
        require(
            hookRegistry.getHooks(
                OPERATOR, chainConfig.uniswap.router, 0, IUniswapRouter.exactInputSingle.selector
            ).defined == defined,
            "uniswap exactInputSingle"
        );
        require(
            hookRegistry.getHooks(
                OPERATOR, chainConfig.uniswap.router, 0, IUniswapRouter.exactOutputSingle.selector
            ).defined == defined,
            "uniswap exactOutputSingle"
        );
    }

    function deployModuleFactory() public {
        vm.broadcast(FUND_ADMIN);
        ModuleFactory moduleFactory = new ModuleFactory();

        console2.log("ModuleFactory: ", address(moduleFactory));
    }

    function deployHookRegistry() public {
        vm.broadcast(FUND_ADMIN);
        HookRegistry hookRegistry = new HookRegistry(STABLE_FUND);

        console2.log("HookRegistry: ", address(hookRegistry));
    }

    function deployTradingModule() public {
        Safe safe = Safe(STABLE_FUND);

        bytes memory moduleCreationCode = abi.encodePacked(
            type(TradingModule).creationCode, abi.encode(STABLE_FUND, HOOK_REGISTRY)
        );

        bytes memory transaction = abi.encodeWithSelector(
            ModuleFactory.deployModule.selector,
            keccak256("deployTradingModule.salt"),
            0,
            moduleCreationCode
        );

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = safe.execTransaction(
            MODULE_FACTORY,
            0,
            transaction,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );

        require(success, "Failed to deploy TradingModule");
        console2.log(
            "TradingModule: ",
            ModuleFactory(MODULE_FACTORY).computeAddress(
                keccak256("deployTradingModule.salt"), keccak256(moduleCreationCode), STABLE_FUND
            )
        );
    }

    function deployUniswapV3Hooks() public {
        vm.broadcast(FUND_ADMIN);
        UniswapV3Hooks uniswapV3Hooks = new UniswapV3Hooks(
            STABLE_FUND, chainConfig.uniswap.positionManager, chainConfig.uniswap.router
        );

        console2.log("UniswapV3Hooks: ", address(uniswapV3Hooks));
    }

    function deployAaveV3Hooks() public {
        vm.broadcast(FUND_ADMIN);
        AaveV3Hooks aaveV3Hooks = new AaveV3Hooks(STABLE_FUND, chainConfig.aave.pool);

        console2.log("AaveV3Hooks: ", address(aaveV3Hooks));
    }

    function _enableAssetTrx(address hook, address asset) private {
        bytes4 selector = bytes4(keccak256("enableAsset(address)"));

        bytes memory transaction = abi.encodeWithSelector(selector, asset);

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = Safe(STABLE_FUND).execTransaction(
            hook,
            0,
            transaction,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );

        require(success, "Failed to enable asset");
    }

    function configureUniswapAssets() public {
        _enableAssetTrx(UNISWAP_V3_HOOKS, ARB_USDCe);
        _enableAssetTrx(UNISWAP_V3_HOOKS, ARB_USDT);
        _enableAssetTrx(UNISWAP_V3_HOOKS, ARB_USDC);
        _enableAssetTrx(UNISWAP_V3_HOOKS, ARB_DAI);
    }

    function configureAaveAssets() public {
        _enableAssetTrx(AAVE_V3_HOOKS, ARB_USDCe);
        _enableAssetTrx(AAVE_V3_HOOKS, ARB_USDT);
        _enableAssetTrx(AAVE_V3_HOOKS, ARB_USDC);
        _enableAssetTrx(AAVE_V3_HOOKS, ARB_DAI);
    }

    function setUniswapHooks() public {
        HookConfig[] memory hookConfigs = new HookConfig[](6);

        /// first all the uniswap hooks

        /// mint position
        hookConfigs[0] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.positionManager,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: INonfungiblePositionManager.mint.selector
        });

        /// increase liquidity
        hookConfigs[1] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.positionManager,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: INonfungiblePositionManager.increaseLiquidity.selector
        });

        /// decreased liqudity
        hookConfigs[2] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.positionManager,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: INonfungiblePositionManager.decreaseLiquidity.selector
        });

        /// collect
        hookConfigs[3] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.positionManager,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: INonfungiblePositionManager.collect.selector
        });

        /// exactInputSingle
        hookConfigs[4] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.router,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: IUniswapRouter.exactInputSingle.selector
        });

        /// exactOutputSingle
        hookConfigs[5] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.router,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: IUniswapRouter.exactOutputSingle.selector
        });

        bytes memory transaction =
            abi.encodeWithSelector(HookRegistry.batchSetHooks.selector, hookConfigs);

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = Safe(STABLE_FUND).execTransaction(
            HOOK_REGISTRY,
            0,
            transaction,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );

        require(success, "Failed to set hooks");
    }

    function removeUniswapHooks() public {
        HookConfig[] memory hookConfigs = new HookConfig[](6);

        /// first all the uniswap hooks

        /// mint position
        hookConfigs[0] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.positionManager,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: INonfungiblePositionManager.mint.selector
        });

        /// increase liquidity
        hookConfigs[1] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.positionManager,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: INonfungiblePositionManager.increaseLiquidity.selector
        });

        /// decreased liqudity
        hookConfigs[2] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.positionManager,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: INonfungiblePositionManager.decreaseLiquidity.selector
        });

        /// collect
        hookConfigs[3] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.positionManager,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: INonfungiblePositionManager.collect.selector
        });

        /// exactInputSingle
        hookConfigs[4] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.router,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: IUniswapRouter.exactInputSingle.selector
        });

        /// exactOutputSingle
        hookConfigs[5] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.uniswap.router,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: UNISWAP_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: IUniswapRouter.exactOutputSingle.selector
        });

        bytes memory transaction =
            abi.encodeWithSelector(HookRegistry.batchRemoveHooks.selector, hookConfigs);

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = Safe(STABLE_FUND).execTransaction(
            HOOK_REGISTRY,
            0,
            transaction,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );

        require(success, "Failed to unset hooks");
    }

    function setAaveHooks() public {
        HookConfig[] memory hookConfigs = new HookConfig[](2);

        /// supply
        hookConfigs[0] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.aave.pool,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: AAVE_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: IPool.supply.selector
        });

        /// withdraw
        hookConfigs[1] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.aave.pool,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: AAVE_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: IPool.withdraw.selector
        });

        bytes memory transaction =
            abi.encodeWithSelector(HookRegistry.batchSetHooks.selector, hookConfigs);

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = Safe(STABLE_FUND).execTransaction(
            HOOK_REGISTRY,
            0,
            transaction,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );

        require(success, "Failed to set hooks");
    }

    function removeAaveHooks() public {
        HookConfig[] memory hookConfigs = new HookConfig[](2);

        /// supply
        hookConfigs[0] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.aave.pool,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: AAVE_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: IPool.supply.selector
        });

        /// withdraw
        hookConfigs[1] = HookConfig({
            operator: OPERATOR,
            target: chainConfig.aave.pool,
            operation: uint8(Enum.Operation.Call),
            beforeTrxHook: AAVE_V3_HOOKS,
            afterTrxHook: address(0),
            targetSelector: IPool.withdraw.selector
        });

        bytes memory transaction =
            abi.encodeWithSelector(HookRegistry.batchRemoveHooks.selector, hookConfigs);

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = Safe(STABLE_FUND).execTransaction(
            HOOK_REGISTRY,
            0,
            transaction,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );

        require(success, "Failed to unset hooks");
    }

    function _approveToken(address token, address spender, uint256 amount) public {
        bytes memory transaction = abi.encodeWithSelector(IERC20.approve.selector, spender, amount);

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = Safe(STABLE_FUND).execTransaction(
            token,
            0,
            transaction,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            transactionSignature
        );

        require(success, "Failed to approve");
    }

    function approveAave() public {
        //max approve
        _approveToken(ARB_USDCe, chainConfig.aave.pool, type(uint256).max);
        _approveToken(ARB_USDT, chainConfig.aave.pool, type(uint256).max);
        _approveToken(ARB_USDC, chainConfig.aave.pool, type(uint256).max);
        _approveToken(ARB_DAI, chainConfig.aave.pool, type(uint256).max);
    }

    function approveUniswap() public {
        // max approve
        _approveToken(ARB_USDCe, chainConfig.uniswap.router, type(uint256).max);
        _approveToken(ARB_USDT, chainConfig.uniswap.router, type(uint256).max);
        _approveToken(ARB_USDC, chainConfig.uniswap.router, type(uint256).max);
        _approveToken(ARB_DAI, chainConfig.uniswap.router, type(uint256).max);

        _approveToken(ARB_USDCe, chainConfig.uniswap.positionManager, type(uint256).max);
        _approveToken(ARB_USDT, chainConfig.uniswap.positionManager, type(uint256).max);
        _approveToken(ARB_USDC, chainConfig.uniswap.positionManager, type(uint256).max);
        _approveToken(ARB_DAI, chainConfig.uniswap.positionManager, type(uint256).max);
    }
}
