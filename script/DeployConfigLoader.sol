// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2, stdJson} from "forge-std/Script.sol";

abstract contract DeployConfigLoader is Script {
    using stdJson for string;

    /// @dev forge needs you to order fields in alphabetical order!!
    struct Gnosis {
        address safeProxyFactory;
        address safeSingleton;
        address tokenCallbackHandler;
    }

    /// @dev forge needs you to order fields in alphabetical order!!
    struct Uniswap {
        address uniswapPositionManager;
        address uniswapRouter;
    }

    /// @dev forge needs you to order fields in alphabetical order!!
    struct AAVE {
        address pool;
    }

    /// @dev forge needs you to order fields in alphabetical order!!
    struct ChainConfig {
        AAVE aave;
        Gnosis gnosis;
        Uniswap uniswap;
    }

    ChainConfig internal chainConfig;
    string internal chain;

    function setUp() public virtual {
        chain = vm.envString("DEPLOYMENT_CHAIN");

        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/script/chain.config.json");
        string memory json = vm.readFile(path);

        bytes memory config = json.parseRaw(string.concat(".", chain));
        chainConfig = abi.decode(config, (ChainConfig));

        console2.log("######################################################");
        console2.log("###             DEPLOYMENT CONFIG                  ###");
        console2.log("######################################################");
        console2.log("Chain: ", chain);
        console2.log("gnosis.safeProxyFactory: ", chainConfig.gnosis.safeProxyFactory);
        console2.log("gnosis.safeSingleton: ", chainConfig.gnosis.safeSingleton);
        console2.log("gnosis.tokenCallbackHandler: ", chainConfig.gnosis.tokenCallbackHandler);
        console2.log("uniswap.uniswapRouter: ", chainConfig.uniswap.uniswapRouter);
        console2.log("uniswap.uniswapPositionManager: ", chainConfig.uniswap.uniswapPositionManager);
        console2.log("aave.pool: ", chainConfig.aave.pool);
    }
}
