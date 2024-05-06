// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console2, stdJson} from "forge-std/Script.sol";
import {DeployConfigLoader} from "@script/DeployConfigLoader.sol";
import "@src/ModuleFactory.sol";
import "@src/HookRegistry.sol";
import "@src/TradingModule.sol";
import "@safe-contracts/Safe.sol";
import "@src/hooks/UniswapV3Hooks.sol";
import "@src/hooks/AaveV3Hooks.sol";

contract ArbStableFundConfig is DeployConfigLoader {
    address payable public constant STABLE_FUND =
        payable(address(0xAB7A4F03d1B5bdB87aDA536c6732E9AFC1D62E9c));
    address public constant FUND_ADMIN = address(0x5822B262EDdA82d2C6A436b598Ff96fA9AB894c4);
    address public constant MODULE_FACTORY = address(0xe30E57cf7D69cBdDD9713AAb109753b5fa1878A5);
    address public constant HOOK_REGISTRY = address(0x5CF7BE32259aE0A1F4c3eb48637c4967477C9648);
    address public constant TRADING_MODULE = address(0x988678e373b8dbaF1FfcaB45c7497126b30A19F0);
    address public constant UNISWAP_V3_HOOKS = address(0x31057Af2739a3DC7ae33A39715279502f08de8c2);
    address public constant AAVE_V3_HOOKS = address(0x8595414D867b69E59207baC0a5392Ba52B7d8595);

    function setUp() public override {
        super.setUp();
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
            STABLE_FUND,
            chainConfig.uniswap.uniswapPositionManager,
            chainConfig.uniswap.uniswapRouter
        );

        console2.log("UniswapV3Hooks: ", address(uniswapV3Hooks));
    }

    function deployAaveV3Hooks() public {
        vm.broadcast(FUND_ADMIN);
        AaveV3Hooks aaveV3Hooks = new AaveV3Hooks(STABLE_FUND, chainConfig.aave.pool);

        console2.log("AaveV3Hooks: ", address(aaveV3Hooks));
    }

    /// TODO: enable assets on UniswapV3Hooks and AaveV3Hooks
    /// TODO: set hooks on HookRegistry
}
