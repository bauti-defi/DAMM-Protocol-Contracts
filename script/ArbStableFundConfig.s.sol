// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {DeployConfigLoader} from "@script/DeployConfigLoader.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@src/ModuleFactory.sol";
import "@src/modules/trading/HookRegistry.sol";
import "@src/modules/trading/TradingModule.sol";
import "@safe-contracts/Safe.sol";
import "@src/hooks/uniswapV3/UniswapV3Hooks.sol";
import "@src/hooks/aaveV3/AaveV3Hooks.sol";

interface IHookGetters {
    function assetWhitelist(address) external view returns (bool);
}

interface IMultiSend {
    /**
     * @dev Sends multiple transactions and reverts all if one fails.
     * @param transactions Encoded transactions. Each transaction is encoded as a packed bytes of
     *                     operation as a uint8 with 0 for a call or 1 for a delegatecall (=> 1 byte),
     *                     to as a address (=> 20 bytes),
     *                     value as a uint256 (=> 32 bytes),
     *                     data length as a uint256 (=> 32 bytes),
     *                     data as bytes.
     *                     see abi.encodePacked for more information on packed encoding
     * @notice This method is payable as delegatecalls keep the msg.value from the previous call
     *         If the calling method (e.g. execTransaction) received ETH this would revert otherwise
     */
    function multiSend(bytes memory transactions) external payable;
}

contract ArbStableFundConfig is DeployConfigLoader {
    address payable public constant STABLE_FUND =
        payable(address(0x07A5DC8f6DD58e5bc88CF2feE1352D6B658522b8));
    address public constant FUND_ADMIN = address(0x5822B262EDdA82d2C6A436b598Ff96fA9AB894c4);
    address public constant MODULE_FACTORY = address(0xe30E57cf7D69cBdDD9713AAb109753b5fa1878A5);
    address public constant HOOK_REGISTRY = address(0x829C5cF481560F6b0ab29B802D90D2baCE20bC0E);
    address public constant TRADING_MODULE = address(0x587F60B0f87e3582f84b77E7F647B6754E04F4d4);
    address public constant UNISWAP_V3_HOOKS = address(0x9C0c182999fD9019c26A8C02fdc9F186ba8f2C57);
    address public constant AAVE_V3_HOOKS = address(0xCeE902D5E970797AB029a9D6CbdCD284c373e250);

    // stablecoins deployed on arbitrum
    address constant ARB_USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant ARB_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant ARB_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
    address public constant MULTISEND_CALL = address(0x9641d764fc13c8B624c04430C7356C1C7C8102e2);

    address constant OPERATOR = address(0x5ed25671f65d0ca26d79326BF571f8AeaF856f00);

    function setUp() public override {
        super.setUp();
    }

    function stablecoins() public pure returns (address[] memory coins) {
        coins = new address[](4);
        coins[0] = ARB_USDCe;
        coins[1] = ARB_USDT;
        coins[2] = ARB_USDC;
        coins[3] = ARB_DAI;
        return coins;
    }

    function _multisendCall(bytes memory payload) private {
        bytes memory transaction = abi.encodeWithSelector(IMultiSend.multiSend.selector, payload);

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = Safe(STABLE_FUND).execTransaction(
            MULTISEND_CALL,
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

        require(success, "multisend failed");
    }

    function verify() public view {
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

    function _enableAsset(address hook, address asset) private pure returns (bytes memory) {
        bytes4 selector = AaveV3Hooks.enableAsset.selector;

        bytes memory transaction = abi.encodeWithSelector(selector, asset);

        return abi.encodePacked(uint8(0), hook, uint256(0), transaction.length, transaction);
    }

    function configureUniswapAssets() public {
        bytes memory payload = abi.encodePacked(
            _enableAsset(UNISWAP_V3_HOOKS, ARB_USDCe),
            _enableAsset(UNISWAP_V3_HOOKS, ARB_USDT),
            _enableAsset(UNISWAP_V3_HOOKS, ARB_USDC),
            _enableAsset(UNISWAP_V3_HOOKS, ARB_DAI)
        );

        _multisendCall(payload);

        for (uint256 i = 0; i < stablecoins().length; i++) {
            require(
                IHookGetters(UNISWAP_V3_HOOKS).assetWhitelist(stablecoins()[i]),
                "Failed to enable uniswap v3 asset"
            );
        }
    }

    function configureAaveAssets() public {
        bytes memory payload = abi.encodePacked(
            _enableAsset(AAVE_V3_HOOKS, ARB_USDCe),
            _enableAsset(AAVE_V3_HOOKS, ARB_USDT),
            _enableAsset(AAVE_V3_HOOKS, ARB_USDC),
            _enableAsset(AAVE_V3_HOOKS, ARB_DAI)
        );

        _multisendCall(payload);

        for (uint256 i = 0; i < stablecoins().length; i++) {
            require(
                IHookGetters(AAVE_V3_HOOKS).assetWhitelist(stablecoins()[i]),
                "Failed to enable aave v3 asset"
            );
        }
    }

    function _setHook(address registry, HookConfig memory hookConfig)
        private
        pure
        returns (bytes memory)
    {
        bytes memory transaction =
            abi.encodeWithSelector(HookRegistry.setHooks.selector, hookConfig);

        return abi.encodePacked(uint8(0), registry, uint256(0), transaction.length, transaction);
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

        bytes memory payload = abi.encodePacked(
            _setHook(HOOK_REGISTRY, hookConfigs[0]),
            _setHook(HOOK_REGISTRY, hookConfigs[1]),
            _setHook(HOOK_REGISTRY, hookConfigs[2]),
            _setHook(HOOK_REGISTRY, hookConfigs[3]),
            _setHook(HOOK_REGISTRY, hookConfigs[4]),
            _setHook(HOOK_REGISTRY, hookConfigs[5])
        );

        _multisendCall(payload);

        for (uint256 i = 0; i < hookConfigs.length; i++) {
            require(
                HookRegistry(HOOK_REGISTRY).getHooks(
                    hookConfigs[i].operator,
                    hookConfigs[i].target,
                    hookConfigs[i].operation,
                    hookConfigs[i].targetSelector
                ).defined,
                "Failed to set uniswap v3 hooks"
            );
        }
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

        bytes memory payload = abi.encodePacked(
            _setHook(HOOK_REGISTRY, hookConfigs[0]),
            _setHook(HOOK_REGISTRY, hookConfigs[1]),
            _setHook(HOOK_REGISTRY, hookConfigs[2]),
            _setHook(HOOK_REGISTRY, hookConfigs[3]),
            _setHook(HOOK_REGISTRY, hookConfigs[4]),
            _setHook(HOOK_REGISTRY, hookConfigs[5])
        );

        _multisendCall(payload);

        for (uint256 i = 0; i < hookConfigs.length; i++) {
            require(
                !HookRegistry(HOOK_REGISTRY).getHooks(
                    hookConfigs[i].operator,
                    hookConfigs[i].target,
                    hookConfigs[i].operation,
                    hookConfigs[i].targetSelector
                ).defined,
                "Failed to unset uniswap v3 hooks"
            );
        }
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

        bytes memory payload = abi.encodePacked(
            _setHook(HOOK_REGISTRY, hookConfigs[0]), _setHook(HOOK_REGISTRY, hookConfigs[1])
        );

        _multisendCall(payload);

        for (uint256 i = 0; i < hookConfigs.length; i++) {
            require(
                HookRegistry(HOOK_REGISTRY).getHooks(
                    hookConfigs[i].operator,
                    hookConfigs[i].target,
                    hookConfigs[i].operation,
                    hookConfigs[i].targetSelector
                ).defined,
                "Failed to set aave v3 hooks"
            );
        }
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

        bytes memory payload = abi.encodePacked(
            _setHook(HOOK_REGISTRY, hookConfigs[0]), _setHook(HOOK_REGISTRY, hookConfigs[1])
        );

        _multisendCall(payload);

        for (uint256 i = 0; i < hookConfigs.length; i++) {
            require(
                !HookRegistry(HOOK_REGISTRY).getHooks(
                    hookConfigs[i].operator,
                    hookConfigs[i].target,
                    hookConfigs[i].operation,
                    hookConfigs[i].targetSelector
                ).defined,
                "Failed to unset aave v3 hooks"
            );
        }
    }

    function _approve(address token, address spender, uint256 amount)
        private
        pure
        returns (bytes memory)
    {
        bytes memory trx = abi.encodeWithSelector(IERC20.approve.selector, spender, amount);

        return abi.encodePacked(uint8(0), token, uint256(0), trx.length, trx);
    }

    function approveAave() public {
        bytes memory approvals = abi.encodePacked(
            _approve(ARB_USDCe, chainConfig.aave.pool, type(uint256).max),
            _approve(ARB_USDT, chainConfig.aave.pool, type(uint256).max),
            _approve(ARB_USDC, chainConfig.aave.pool, type(uint256).max),
            _approve(ARB_DAI, chainConfig.aave.pool, type(uint256).max)
        );

        _multisendCall(approvals);

        for (uint256 i = 0; i < stablecoins().length; i++) {
            require(
                IERC20(stablecoins()[i]).allowance(STABLE_FUND, chainConfig.aave.pool)
                    == type(uint256).max,
                "Failed to approve tokent to aave"
            );
        }
    }

    function approveUniswap() public {
        bytes memory approvals = abi.encodePacked(
            _approve(ARB_USDCe, chainConfig.uniswap.router, type(uint256).max),
            _approve(ARB_USDT, chainConfig.uniswap.router, type(uint256).max),
            _approve(ARB_USDC, chainConfig.uniswap.router, type(uint256).max),
            _approve(ARB_DAI, chainConfig.uniswap.router, type(uint256).max),
            _approve(ARB_USDCe, chainConfig.uniswap.positionManager, type(uint256).max),
            _approve(ARB_USDT, chainConfig.uniswap.positionManager, type(uint256).max),
            _approve(ARB_USDC, chainConfig.uniswap.positionManager, type(uint256).max),
            _approve(ARB_DAI, chainConfig.uniswap.positionManager, type(uint256).max)
        );

        _multisendCall(approvals);

        for (uint256 i = 0; i < stablecoins().length; i++) {
            require(
                IERC20(stablecoins()[i]).allowance(STABLE_FUND, chainConfig.uniswap.router)
                    == type(uint256).max,
                "Failed to approve token to uniswap router"
            );
            require(
                IERC20(stablecoins()[i]).allowance(STABLE_FUND, chainConfig.uniswap.positionManager)
                    == type(uint256).max,
                "Failed to approve toke to uniswap position manager"
            );
        }
    }
}
