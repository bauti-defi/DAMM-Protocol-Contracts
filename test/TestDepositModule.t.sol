// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestBaseFund} from "@test/base/TestBaseFund.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {Periphery} from "@src/modules/deposit/Periphery.sol";
import {
    DepositIntent,
    WithdrawIntent,
    WithdrawOrder,
    DepositOrder,
    Role,
    AccountStatus,
    AssetPolicy,
    UserAccountInfo
} from "@src/modules/deposit/Structs.sol";
import {NATIVE_ASSET} from "@src/libs/Constants.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";

uint8 constant VALUATION_DECIMALS = 18;
uint256 constant VAULT_DECIMAL_OFFSET = 1;

contract TestDepositModule is TestBaseFund, TestBaseProtocol {
    using MessageHashUtils for bytes;

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    EulerRouter internal oracleRouter;
    Periphery internal periphery;
    MockERC20 internal mockToken1;
    MockERC20 internal mockToken2;

    address alice;
    uint256 internal alicePK;
    address bob;
    uint256 internal bobPK;
    address relayer;

    uint256 mock1Unit;
    uint256 mock2Unit;
    uint256 periphery1Unit;

    function setUp() public override(TestBaseFund, TestBaseProtocol) {
        TestBaseFund.setUp();
        TestBaseProtocol.setUp();

        relayer = makeAddr("Relayer");

        (alice, alicePK) = makeAddrAndKey("Alice");

        (bob, bobPK) = makeAddrAndKey("Bob");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 1);
        vm.label(address(fund), "Fund");

        require(address(fund).balance == 0, "Fund should not have balance");

        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

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
                        VALUATION_DECIMALS, // must be same as underlying oracles response denomination
                        payable(address(fund)),
                        address(oracleRouter),
                        address(0)
                    )
                )
            )
        );

        assertTrue(fund.isModuleEnabled(address(periphery)), "Periphery not module");

        /// @notice this much match the vault implementation
        periphery1Unit = 1 * 10 ** (periphery.decimals() + VAULT_DECIMAL_OFFSET);

        mockToken1 = new MockERC20(18);
        vm.label(address(mockToken1), "MockToken1");

        mockToken2 = new MockERC20(6);
        vm.label(address(mockToken2), "MockToken2");

        mock1Unit = 1 * 10 ** mockToken1.decimals();
        mock2Unit = 1 * 10 ** mockToken2.decimals();

        // lets enable assets on the fund
        vm.startPrank(address(fund));
        fund.setAssetOfInterest(address(mockToken1));
        periphery.enableAsset(
            address(mockToken1),
            AssetPolicy({
                minimumDeposit: 1000,
                minimumWithdrawal: 1000,
                canDeposit: true,
                canWithdraw: true,
                permissioned: false,
                enabled: true
            })
        );

        fund.setAssetOfInterest(address(mockToken2));
        periphery.enableAsset(
            address(mockToken2),
            AssetPolicy({
                minimumDeposit: 1000,
                minimumWithdrawal: 1000,
                canDeposit: true,
                canWithdraw: true,
                permissioned: false,
                enabled: true
            })
        );

        // native eth
        fund.setAssetOfInterest(NATIVE_ASSET);
        periphery.enableAsset(
            NATIVE_ASSET,
            AssetPolicy({
                minimumDeposit: 1000,
                minimumWithdrawal: 1000,
                canDeposit: false,
                canWithdraw: false,
                permissioned: false,
                enabled: true
            })
        );
        vm.stopPrank();

        // also enable the accounts to periphery
        vm.startPrank(address(fund));
        periphery.openAccount(alice, Role.USER);
        periphery.openAccount(bob, Role.USER);
        vm.stopPrank();

        MockPriceOracle mockPriceOracle = new MockPriceOracle(
            address(mockToken1),
            address(periphery),
            1 * 10 ** VALUATION_DECIMALS,
            VALUATION_DECIMALS
        );
        vm.label(address(mockPriceOracle), "MockPriceOracle1");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(mockToken1), address(periphery), address(mockPriceOracle));

        mockPriceOracle = new MockPriceOracle(
            address(mockToken2),
            address(periphery),
            2 * 10 ** VALUATION_DECIMALS,
            VALUATION_DECIMALS
        );
        vm.label(address(mockPriceOracle), "MockPriceOracle2");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(mockToken2), address(periphery), address(mockPriceOracle));
    }

    function _depositOrder(address user, uint256 userPK, address token, uint256 amount)
        internal
        returns (DepositOrder memory)
    {
        DepositIntent memory intent = DepositIntent({
            user: user,
            asset: token,
            amount: amount,
            deadline: block.timestamp + 1000,
            minSharesOut: 0,
            relayerTip: 0,
            nonce: periphery.getUserAccountInfo(user).nonce
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return DepositOrder({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function _withdrawOrder(address user, uint256 userPK, address to, address asset, uint256 amount)
        internal
        returns (WithdrawOrder memory)
    {
        WithdrawIntent memory intent = WithdrawIntent({
            user: user,
            to: to,
            asset: asset,
            amount: amount,
            maxSharesIn: 0,
            deadline: block.timestamp + 1000,
            relayerTip: 0,
            nonce: periphery.getUserAccountInfo(user).nonce
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return WithdrawOrder({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function test_deposit_withdraw() public {
        mockToken1.mint(alice, 100_000_000 * 10 ** mockToken1.decimals());
        mockToken1.mint(bob, 100_000_000 * 10 ** mockToken1.decimals());

        vm.prank(alice);
        mockToken1.approve(address(periphery), type(uint256).max);

        vm.prank(bob);
        mockToken1.approve(address(periphery), type(uint256).max);

        vm.prank(relayer);
        periphery.deposit(_depositOrder(alice, alicePK, address(mockToken1), mock1Unit));

        assertEq(periphery.vault().balanceOf(alice), periphery1Unit);

        /// mock fund gains 1 unit of mockToken1
        mockToken1.mint(address(fund), mock1Unit);

        uint256 aliceBalance = periphery.vault().balanceOf(alice);

        assertApproxEqRel(
            oracleRouter.getQuote(
                periphery.vault().previewRedeem(aliceBalance),
                address(periphery),
                address(mockToken1)
            ),
            2 * mock1Unit,
            0.1e18
        );
        assertApproxEqRel(
            oracleRouter.getQuote(
                periphery.vault().previewRedeem(aliceBalance),
                address(periphery),
                address(mockToken2)
            ),
            1 * mock2Unit,
            0.1e18
        );

        vm.prank(relayer);
        periphery.deposit(_depositOrder(bob, bobPK, address(mockToken1), mock1Unit));

        uint256 bobBalance = periphery.vault().balanceOf(bob);

        assertApproxEqRel(
            oracleRouter.getQuote(
                periphery.vault().previewRedeem(aliceBalance),
                address(periphery),
                address(mockToken1)
            ),
            2 * mock1Unit,
            0.1e18
        );
        assertApproxEqRel(
            oracleRouter.getQuote(
                periphery.vault().previewRedeem(bobBalance), address(periphery), address(mockToken1)
            ),
            1 * mock1Unit,
            0.1e18
        );

        /// mock fund gains 3 units of mockToken1
        mockToken1.mint(address(fund), 3 * mock1Unit);

        assertApproxEqRel(
            oracleRouter.getQuote(
                periphery.vault().previewRedeem(aliceBalance),
                address(periphery),
                address(mockToken1)
            ),
            4 * mock1Unit,
            0.1e18
        );
        assertApproxEqRel(
            oracleRouter.getQuote(
                periphery.vault().previewRedeem(bobBalance), address(periphery), address(mockToken1)
            ),
            2 * mock1Unit,
            0.1e18
        );

        address claimer = makeAddr("Claimer");

        vm.prank(relayer);
        periphery.withdraw(_withdrawOrder(alice, alicePK, claimer, address(mockToken1), mock1Unit));
    }
}
