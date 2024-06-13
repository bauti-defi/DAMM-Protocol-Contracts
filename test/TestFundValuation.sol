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
import {
    ARB_USDC_USD_FEED,
    ARB_USDT_USD_FEED,
    ARB_DAI_USD_FEED,
    ARB_ETH_USD_FEED
} from "@test/forked/ChainlinkOracleFeeds.sol";
import {Periphery} from "@src/modules/deposit/Periphery.sol";
import {AssetPolicy} from "@src/modules/deposit/Structs.sol";
import {IFund} from "@src/interfaces/IFund.sol";
import {FundNotFullyDivested_Error} from "@src/modules/deposit/Errors.sol";
import {POSITION_OPENER, POSITION_CLOSER, NULL} from "@src/FundCallbackHandler.sol";
import "@src/interfaces/IOwnable.sol";
import "@src/libs/Constants.sol";

// keccak256("fallback_manager.handler.address")
bytes32 constant FALLBACK_HANDLER_STORAGE_SLOT =
    0x6c9a6c4a39284e37ed1cf53d337577d14212a4870fb976a4366c693b939918d5;

uint256 constant USD_DECIMALS = 8;

contract TestFundValuation is Test, TestBaseProtocol, TestBaseGnosis, TokenMinter {
    address internal fundAdmin;
    uint256 internal fundAdminPK;
    IFund internal fund;
    FundCallbackHandler internal callbackHandler;
    EulerRouter internal oracleRouter;
    Periphery internal periphery;

    address positionOpenerCloser;

    uint256 internal arbitrumFork;

    function setUp() public override(TestBaseProtocol, TestBaseGnosis, TokenMinter) {
        arbitrumFork = vm.createFork(vm.envString("ARBI_RPC_URL"));

        vm.selectFork(arbitrumFork);
        assertEq(vm.activeFork(), arbitrumFork);

        vm.rollFork(218796378);

        TestBaseProtocol.setUp();
        TestBaseGnosis.setUp();
        TokenMinter.setUp();

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = IFund(address(deploySafe(admins, 1)));

        callbackHandler = new FundCallbackHandler(address(fund));

        positionOpenerCloser = makeAddr("PositionOpener");

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
            deployModule(
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
                        USD_DECIMALS, // must be same as underlying chainlink oracles. USD = 8
                        payable(address(fund)),
                        address(oracleRouter),
                        address(0)
                    )
                )
            )
        );

        assertTrue(fund.isModuleEnabled(address(periphery)), "Periphery not module");

        // set up position opener
        addModuleWithRoles(
            payable(address(fund)),
            fundAdmin,
            fundAdminPK,
            positionOpenerCloser,
            POSITION_OPENER | POSITION_CLOSER
        );

        assertTrue(fund.isModuleEnabled(positionOpenerCloser), "Position opener not module");
        assertTrue(
            fund.hasAllRoles(positionOpenerCloser, POSITION_OPENER),
            "Position opener not authorized"
        );

        // lets enable assets on the fund
        vm.startPrank(address(fund));
        IFund(address(fund)).addAssetOfInterest(ARB_USDC);
        IFund(address(fund)).addAssetOfInterest(ARB_USDT);
        IFund(address(fund)).addAssetOfInterest(ARB_DAI);
        IFund(address(fund)).addAssetOfInterest(ARB_USDCe);

        // native eth
        IFund(address(fund)).addAssetOfInterest(NATIVE_ASSET);
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

        // setup DAI/USD oracle
        chainlinkOracle =
            new ChainlinkOracle(ARB_DAI, address(periphery), ARB_DAI_USD_FEED, 24 hours);
        vm.label(address(chainlinkOracle), "ChainlinkOracle-DAI");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(ARB_DAI, address(periphery), address(chainlinkOracle));

        // setup USDCe/USD oracle
        chainlinkOracle =
            new ChainlinkOracle(ARB_USDCe, address(periphery), ARB_USDC_USD_FEED, 24 hours);
        vm.label(address(chainlinkOracle), "ChainlinkOracle-USDCe");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(ARB_USDCe, address(periphery), address(chainlinkOracle));

        // setup ETH/USD oracle
        chainlinkOracle =
            new ChainlinkOracle(NATIVE_ASSET, address(periphery), ARB_ETH_USD_FEED, 24 hours);
        vm.label(address(chainlinkOracle), "ChainlinkOracle-ETH");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(NATIVE_ASSET, address(periphery), address(chainlinkOracle));
    }

    function test_cannot_valuate_fund_with_open_positions() public {
        assertEq(periphery.totalAssets(), 0, "Total assets should be 0");
        assertEq(fund.hasOpenPositions(), false, "No open positions");

        // the caller must be an active module
        vm.prank(positionOpenerCloser);
        fund.onPositionOpened(bytes32(uint256(1)));

        mintUSDC(address(fund), 1000 * (10 ** 6));
        mintUSDT(address(fund), 1000 * (10 ** 6));
        mintDAI(address(fund), 1000 * (10 ** 18));
        mintUSDCe(address(fund), 1000 * (10 ** 6));

        vm.expectRevert();
        periphery.totalAssets();

        assertEq(fund.hasOpenPositions(), true, "No open positions");

        // close the position
        vm.prank(positionOpenerCloser);
        fund.onPositionClosed(bytes32(uint256(1)));

        assertEq(fund.hasOpenPositions(), false, "No open positions");
        assertTrue(periphery.totalAssets() > 0, "Total assets should not be 0");
    }

    function test_valuate_fund_in_USD(uint256 a, uint256 b, uint256 c, uint256 d, uint256 e)
        public
    {
        vm.assume(a < 1e20 && a > 0);
        vm.assume(b < 1e20 && b > 0);
        vm.assume(c < 1e20 && c > 0);
        vm.assume(d < 1e20 && d > 0);
        vm.assume(e < 1e30 && e > 0);
        assertEq(periphery.totalAssets(), 0, "Total assets should be 0");

        // price at current block: 218796378
        uint256 eth_usd_price = 384782218166;

        // mint some USDC and USDT
        mintUSDC(address(fund), a * (10 ** 6));
        mintUSDT(address(fund), b * (10 ** 6));
        mintDAI(address(fund), c * (10 ** 18));
        mintUSDCe(address(fund), d * (10 ** 6));
        deal(address(fund), e);

        // total assets in USD
        assertApproxEqRel(
            periphery.totalAssets(),
            (a + b + c + d) * (10 ** USD_DECIMALS) + e * eth_usd_price / 1 ether,
            0.1e18,
            "Total assets should be about same in USD"
        );
    }
}
