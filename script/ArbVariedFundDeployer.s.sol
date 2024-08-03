// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {DeployConfigLoader} from "@script/DeployConfigLoader.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@src/libs/ModuleLib.sol";
import "@src/modules/transact/HookRegistry.sol";
import "@src/modules/transact/TransactionModule.sol";
import "@safe-contracts/Safe.sol";
import "@src/hooks/uniswapV3/UniswapV3Hooks.sol";
import "@src/hooks/aaveV3/AaveV3Hooks.sol";
import "@safe-contracts/libraries/CreateCall.sol";
import "@openzeppelin-contracts/utils/Create2.sol";
import "@src/FundFactory.sol";

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

contract ArbVariedFundDeployer is DeployConfigLoader {
    address payable public constant FUND =
        payable(address(0x8c9dcFE0B57561bDBd03e6f15f0e6466eC526cd2));
    address public constant FUND_ADMIN = address(0x5822B262EDdA82d2C6A436b598Ff96fA9AB894c4);

    address public constant FUND_FACTORY = address(0xd461a570c2254DeE800b89aEb3582C25f89e8f4C);
    address public constant CREATE_CALL = address(0x9b35Af71d77eaf8d7e40252370304687390A1A52);
    address public constant MODULE_LIB = address(0xC813E2752C387Fd716df7e99d0ED099b718600bF);

    address public constant HOOK_REGISTRY = address(0xB891Ca2C442014D38E336464F9dBc9229C8ab6aD);
    address public constant TRANSACTION_MODULE = address(0x8223d1F6eab60cB29fCf61eE3Ae418Be34B5Cb92);
    address public constant UNISWAP_V3_HOOKS = address(0x7A0ec072cF5E47cbA02dc58F31555C1dd2b4ff4C);
    address public constant AAVE_V3_HOOKS = address(0xcdf29924909cE3C2689827E5f906aa4a83CAb648);

    // tokens deployed on arbitrum
    address constant ARB_USDCe = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address constant ARB_USDT = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address constant ARB_USDC = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address constant ARB_DAI = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    address constant WETH = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address constant ARB = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address constant wstETH = address(0x5979D7b546E38E414F7E9822514be443A4800529);
    address constant WBTC = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    address constant LINK = address(0xf97f4df75117a78c1A5a0DBb814Af92458539FB4);
    address constant CRV = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address constant UNI = address(0xFa7F8980b0f1E64A2062791cc3b0871572f1F7f0);
    address constant GMX = address(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    address constant LDO = address(0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60);

    address public constant MULTISEND_CALL = address(0x9641d764fc13c8B624c04430C7356C1C7C8102e2);

    address constant OPERATOR = address(0x8cCF048cEd9882c1857Bfc3cf767117600C3eb3F);

    function setUp() public override {
        super.setUp();

        vm.label(CREATE_CALL, "CreateCall");
        vm.label(MODULE_LIB, "ModuleLib");
        vm.label(HOOK_REGISTRY, "HookRegistry");
        vm.label(TRANSACTION_MODULE, "TransactionModule");
        vm.label(UNISWAP_V3_HOOKS, "UniswapV3Hooks");
        vm.label(AAVE_V3_HOOKS, "AaveV3Hooks");
        vm.label(FUND_ADMIN, "FundAdmin");
    }

    function tokens() public pure returns (address[] memory coins) {
        coins = new address[](13);
        coins[0] = ARB_USDCe;
        coins[1] = ARB_USDT;
        coins[2] = ARB_USDC;
        coins[3] = ARB_DAI;
        coins[4] = WETH;
        coins[5] = ARB;
        coins[6] = wstETH;
        coins[7] = WBTC;
        coins[8] = LINK;
        coins[9] = CRV;
        coins[10] = UNI;
        coins[11] = GMX;
        coins[12] = LDO;
        return coins;
    }

    function _multisendCall(bytes memory payload) private {
        bytes memory transaction = abi.encodeWithSelector(IMultiSend.multiSend.selector, payload);

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = Safe(FUND).execTransaction(
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

    function deployModuleLib() public {
        vm.broadcast(FUND_ADMIN);
        ModuleLib moduleLib = new ModuleLib();

        console2.log("ModuleLib: ", address(moduleLib));
    }

    function deployFundFactory() public {
        vm.broadcast(FUND_ADMIN);
        FundFactory factory = new FundFactory();

        console2.log("FundFactory: ", address(factory));
    }

    function deployFund() public {
        FundFactory factory = FundFactory(FUND_FACTORY);

        address[] memory admins = new address[](1);
        admins[0] = FUND_ADMIN;

        uint256 threshold = 1;

        vm.broadcast(FUND_ADMIN);
        address fund = address(
            factory.deployFund(
                chainConfig.gnosis.safeProxyFactory,
                chainConfig.gnosis.safeSingleton,
                admins,
                threshold
            )
        );

        console2.log("Fund: ", fund);
    }

    function deployHookRegistry() public {
        vm.broadcast(FUND_ADMIN);
        HookRegistry hookRegistry = new HookRegistry(FUND);

        console2.log("HookRegistry: ", address(hookRegistry));
    }

    function deployTransactionModule() public {
        Safe safe = Safe(FUND);

        bytes memory moduleCreationCode =
            abi.encodePacked(type(TransactionModule).creationCode, abi.encode(FUND, HOOK_REGISTRY));

        bytes memory transaction = abi.encodeWithSelector(
            ModuleLib.deployModule.selector,
            keccak256("deployTransactionModule.salt"),
            0,
            moduleCreationCode
        );

        bytes memory transactionSignature = abi.encodePacked(
            bytes32(uint256(uint160(FUND_ADMIN))), bytes32(uint256(uint160(FUND_ADMIN))), uint8(1)
        );

        vm.broadcast(FUND_ADMIN);
        bool success = safe.execTransaction(
            MODULE_LIB,
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

        require(success, "Failed to deploy TransactionModule");
        console2.log(
            "TransactionModule: ",
            Create2.computeAddress(
                keccak256("deployTransactionModule.salt"),
                keccak256(moduleCreationCode),
                CREATE_CALL
            )
        );
    }

    function deployUniswapV3Hooks() public {
        vm.broadcast(FUND_ADMIN);
        UniswapV3Hooks uniswapV3Hooks = new UniswapV3Hooks(
            FUND, chainConfig.uniswap.positionManager, chainConfig.uniswap.router
        );

        console2.log("UniswapV3Hooks: ", address(uniswapV3Hooks));
    }

    function deployAaveV3Hooks() public {
        vm.broadcast(FUND_ADMIN);
        AaveV3Hooks aaveV3Hooks = new AaveV3Hooks(FUND, chainConfig.aave.pool);

        console2.log("AaveV3Hooks: ", address(aaveV3Hooks));
    }

    function _enableAsset(address hook, address asset) private pure returns (bytes memory) {
        bytes4 selector = AaveV3Hooks.enableAsset.selector;

        bytes memory transaction = abi.encodeWithSelector(selector, asset);

        return abi.encodePacked(uint8(0), hook, uint256(0), transaction.length, transaction);
    }

    function configureUniswapAssets() public {
        bytes memory payload = "";

        for (uint256 i = 0; i < tokens().length; i++) {
            payload = abi.encodePacked(payload, _enableAsset(UNISWAP_V3_HOOKS, tokens()[i]));
        }

        _multisendCall(payload);

        for (uint256 i = 0; i < tokens().length; i++) {
            require(
                IHookGetters(UNISWAP_V3_HOOKS).assetWhitelist(tokens()[i]),
                "Failed to enable uniswap v3 asset"
            );
        }
    }

    function configureAaveAssets() public {
        bytes memory payload = "";

        for (uint256 i = 0; i < tokens().length; i++) {
            payload = abi.encodePacked(payload, _enableAsset(AAVE_V3_HOOKS, tokens()[i]));
        }

        _multisendCall(payload);

        for (uint256 i = 0; i < tokens().length; i++) {
            require(
                IHookGetters(AAVE_V3_HOOKS).assetWhitelist(tokens()[i]),
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
        bytes memory approvals = "";
        for (uint256 i = 0; i < tokens().length; i++) {
            approvals = abi.encodePacked(
                approvals, _approve(tokens()[i], chainConfig.aave.pool, type(uint256).max)
            );
        }

        _multisendCall(approvals);

        for (uint256 i = 0; i < tokens().length; i++) {
            require(
                IERC20(tokens()[i]).allowance(FUND, chainConfig.aave.pool) == type(uint256).max,
                "Failed to approve tokent to aave"
            );
        }
    }

    function approveUniswapRouter() public {
        bytes memory approvals = "";

        for (uint256 i = 0; i < tokens().length; i++) {
            approvals = abi.encodePacked(
                approvals, _approve(tokens()[i], chainConfig.uniswap.router, type(uint256).max)
            );
        }

        _multisendCall(approvals);

        for (uint256 i = 0; i < tokens().length; i++) {
            require(
                IERC20(tokens()[i]).allowance(FUND, chainConfig.uniswap.router) == type(uint256).max,
                "Failed to approve token to uniswap router"
            );
        }
    }

    function approveUniswapPositionManager() public {
        bytes memory approvals = "";

        for (uint256 i = 0; i < tokens().length; i++) {
            approvals = abi.encodePacked(
                approvals,
                _approve(tokens()[i], chainConfig.uniswap.positionManager, type(uint256).max)
            );
        }

        _multisendCall(approvals);

        for (uint256 i = 0; i < tokens().length; i++) {
            require(
                IERC20(tokens()[i]).allowance(FUND, chainConfig.uniswap.positionManager)
                    == type(uint256).max,
                "Failed to approve toke to uniswap position manager"
            );
        }
    }

    function approveUniswap() public {
        approveUniswapRouter();
        approveUniswapPositionManager();
    }

    function approveAll() public {
        approveAave();
        approveUniswap();
    }
}
