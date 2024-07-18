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

contract ArbFundDeployer is DeployConfigLoader {
    address payable public constant DAMM_FUND =
        payable(address(0x964Bb08b217C3E5D4380A54e5f7c51Bd1f2a68DB));
    address public constant FUND_ADMIN = address(0x5822B262EDdA82d2C6A436b598Ff96fA9AB894c4);

    address public constant CREATE_CALL = address(0x9b35Af71d77eaf8d7e40252370304687390A1A52);

    address public constant MODULE_LIB = address(0xe30E57cf7D69cBdDD9713AAb109753b5fa1878A5);
    address public constant HOOK_REGISTRY = address(0xfAcC9bE6e79034C679B0A1E0de407B58Fb240E0c);
    address public constant TRANSACTION_MODULE = address(0x20580451fEc6B5dc824A2d6D4cC295c1Cf3f0d3E);

    address constant OPERATOR = address(0x5ed25671f65d0ca26d79326BF571f8AeaF856f00);

    function setUp() public override {
        super.setUp();

        vm.label(CREATE_CALL, "CreateCall");
        vm.label(MODULE_LIB, "ModuleLib");
        vm.label(HOOK_REGISTRY, "HookRegistry");
        vm.label(TRANSACTION_MODULE, "TransactionModule");
        vm.label(FUND_ADMIN, "FundAdmin");
    }

    function deployModuleLib() public {
        vm.broadcast(FUND_ADMIN);
        ModuleLib moduleLib = new ModuleLib();

        console2.log("ModuleLib: ", address(moduleLib));
    }

    function deployHookRegistry() public {
        vm.broadcast(FUND_ADMIN);
        HookRegistry hookRegistry = new HookRegistry(DAMM_FUND);

        console2.log("HookRegistry: ", address(hookRegistry));
    }

    function deployTransactionModule() public {
        Safe safe = Safe(DAMM_FUND);

        bytes memory moduleCreationCode = abi.encodePacked(
            type(TransactionModule).creationCode, abi.encode(DAMM_FUND, HOOK_REGISTRY)
        );

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
            DAMM_FUND, chainConfig.uniswap.positionManager, chainConfig.uniswap.router
        );

        console2.log("UniswapV3Hooks: ", address(uniswapV3Hooks));
    }

    function deployAaveV3Hooks() public {
        vm.broadcast(FUND_ADMIN);
        AaveV3Hooks aaveV3Hooks = new AaveV3Hooks(DAMM_FUND, chainConfig.aave.pool);

        console2.log("AaveV3Hooks: ", address(aaveV3Hooks));
    }
}
