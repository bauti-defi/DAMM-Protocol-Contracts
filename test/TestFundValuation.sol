// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {FundCallbackHandler} from "@src/FundCallbackHandler.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {TokenMinter} from "@test/forked/TokenMinter.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {ChainlinkOracle} from "@euler-price-oracle/adapter/chainlink/ChainlinkOracle.sol";
import {ARB_USDC_USD_FEED, ARB_USDT_USD_FEED} from "@test/forked/ChainlinkOracleFeeds.sol";
import {Periphery} from "@src/deposits/Periphery.sol";
import {AssetPolicy} from "@src/deposits/DepositWithdrawStructs.sol";
import {IFund} from "@src/interfaces/IFund.sol";

// keccak256("fallback_manager.handler.address")
bytes32 constant FALLBACK_HANDLER_STORAGE_SLOT =
    0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;

contract TestFundValuation is Test, TestBaseProtocol, TestBaseGnosis, TokenMinter {
    address internal fundAdmin;
    uint256 internal fundAdminPK;
    SafeL2 internal fund;
    FundCallbackHandler internal callbackHandler;
    EulerRouter internal oracleRouter;
    Periphery internal periphery;

    uint256 internal arbitrumFork;

    function setUp() public override(TestBaseProtocol, TestBaseGnosis, TokenMinter) {
        arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));

        vm.selectFork(arbitrumFork);
        assertEq(vm.activeFork(), arbitrumFork);

        vm.rollFork(218784958);

        TestBaseProtocol.setUp();
        TestBaseGnosis.setUp();
        TokenMinter.setUp();

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = deploySafe(admins, 1);

        callbackHandler = new FundCallbackHandler(address(fund));

        vm.prank(address(fund));
        fund.setFallbackHandler(address(callbackHandler));

        vm.label(address(fund), "Fund");
        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");
        assertEq(
            address(uint160(uint256(vm.load(address(fund), FALLBACK_HANDLER_STORAGE_SLOT)))),
            address(callbackHandler),
            "Fallback handler not set"
        );

        vm.prank(address(fund));
        oracleRouter = new EulerRouter(address(fund));
        vm.label(address(oracleRouter), "OracleRouter");

        // deploy periphery using module factory
        periphery = Periphery(
            deployContract(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("periphery"),
                0,
                abi.encodePacked(
                    type(Periphery).creationCode,
                    abi.encode(
                        "TestVault",
                        "TV",
                        8, // must be same as underlying chainlink oracles. USD = 8
                        payable(address(fund)),
                        address(oracleRouter),
                        address(0)
                    )
                )
            )
        );

        // lets enable USDC and USDT on the fund
        vm.startPrank(address(fund));
        IFund(address(fund)).addAssetOfInterest(ARB_USDC);
        IFund(address(fund)).addAssetOfInterest(ARB_USDT);
        vm.stopPrank();

        // now we enable an asset policy for both USDC and USDT
        vm.startPrank(address(fund));
        periphery.enableAsset(
            ARB_USDC,
            AssetPolicy({
                minimumDeposit: 1000 ether,
                minimumWithdrawal: 1000 ether,
                canDeposit: true,
                canWithdraw: true,
                permissioned: false,
                enabled: true
            })
        );
        periphery.enableAsset(
            ARB_USDT,
            AssetPolicy({
                minimumDeposit: 1000 ether,
                minimumWithdrawal: 1000 ether,
                canDeposit: true,
                canWithdraw: true,
                permissioned: false,
                enabled: true
            })
        );
        vm.stopPrank();

        // setup USDC/USD oracle
        ChainlinkOracle chainlinkOracle =
            new ChainlinkOracle(ARB_USDC, address(periphery), ARB_USDC_USD_FEED, 24 hours);
        vm.label(address(chainlinkOracle), "ChainlinkOracle-USDC");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(ARB_USDC, address(periphery), address(chainlinkOracle));

        // setup USDT/USD oracle
        chainlinkOracle =
            new ChainlinkOracle(ARB_USDT, address(periphery), ARB_USDT_USD_FEED, 24 hours);
        vm.label(address(chainlinkOracle), "ChainlinkOracle-USDT");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(ARB_USDT, address(periphery), address(chainlinkOracle));
    }

    function test_this() public {
        assertEq(periphery.totalAssets(), 0, "Total assets should be 0");

        // mint some USDC and USDT
        mintUSDC(address(fund), 1 * (10 ** 6));
        mintUSDT(address(fund), 1 * (10 ** 6));

        assertEq(periphery.totalAssets(), 2, "Total assets should be 2");
    }
}
