// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestBaseFund} from "@test/base/TestBaseFund.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {PeripheryV2} from "@src/modules/deposit/PeripheryV2.sol";
import {FundValuationOracle} from "@src/oracles/FundValuationOracle.sol";
import "@src/modules/deposit/StructsV2.sol";
import {NATIVE_ASSET} from "@src/libs/Constants.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import {console2} from "@forge-std/Test.sol";

uint8 constant VALUATION_DECIMALS = 18;
uint256 constant VAULT_DECIMAL_OFFSET = 1;

contract TestDepositWithdrawV2 is TestBaseFund, TestBaseProtocol {
    using MessageHashUtils for bytes;

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    EulerRouter internal oracleRouter;
    PeripheryV2 internal periphery;
    MockERC20 internal mockToken1;
    MockERC20 internal mockToken2;

    address alice;
    uint256 internal alicePK;
    address bob;
    uint256 internal bobPK;
    address relayer;
    address feeRecipient;
    uint256 internal feeRecipientPK;

    uint256 mock1Unit;
    uint256 mock2Unit;
    uint256 oneUnitOfAccount;

    function setUp() public override(TestBaseFund, TestBaseProtocol) {
        TestBaseFund.setUp();
        TestBaseProtocol.setUp();

        (feeRecipient, feeRecipientPK) = makeAddrAndKey("FeeRecipient");

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
        periphery = PeripheryV2(
            deployModule(
                payable(address(fund)),
                fundAdmin,
                fundAdminPK,
                bytes32("periphery"),
                0,
                abi.encodePacked(
                    type(PeripheryV2).creationCode,
                    abi.encode(
                        "TestVault",
                        "TV",
                        VALUATION_DECIMALS, // must be same as underlying oracles response denomination
                        payable(address(fund)),
                        address(oracleRouter),
                        address(fund),
                        /// fund is admin
                        feeRecipient
                    )
                )
            )
        );

        assertTrue(fund.isModuleEnabled(address(periphery)), "Periphery not module");

        /// @notice this much match the vault implementation
        oneUnitOfAccount = 1 * 10 ** (periphery.unitOfAccount().decimals() + VAULT_DECIMAL_OFFSET);

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

        address unitOfAccount = address(periphery.unitOfAccount());

        FundValuationOracle valuationOracle = new FundValuationOracle(address(oracleRouter));
        vm.label(address(valuationOracle), "FundValuationOracle");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(fund), unitOfAccount, address(valuationOracle));

        MockPriceOracle mockPriceOracle = new MockPriceOracle(
            address(mockToken1), unitOfAccount, 1 * 10 ** VALUATION_DECIMALS, VALUATION_DECIMALS
        );
        vm.label(address(mockPriceOracle), "MockPriceOracle1");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(mockToken1), unitOfAccount, address(mockPriceOracle));

        mockPriceOracle = new MockPriceOracle(
            address(mockToken2), unitOfAccount, 2 * 10 ** VALUATION_DECIMALS, VALUATION_DECIMALS
        );
        vm.label(address(mockPriceOracle), "MockPriceOracle2");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(mockToken2), unitOfAccount, address(mockPriceOracle));
    }

    modifier approveAll(address user) {
        vm.startPrank(user);
        mockToken1.approve(address(periphery), type(uint256).max);
        periphery.vault().approve(address(periphery), type(uint256).max);
        vm.stopPrank();

        _;
    }

    function _depositOrder(
        uint256 accountId,
        address user,
        uint256 userPK,
        address token,
        uint256 amount
    ) internal view returns (SignedDepositIntent memory) {
        DepositIntent memory intent = DepositIntent({
            deposit: DepositOrder({
                accountId: accountId,
                recipient: user,
                asset: token,
                amount: amount,
                deadline: block.timestamp + 1000,
                minSharesOut: 0
            }),
            chaindId: block.chainid,
            relayerTip: 0,
            nonce: periphery.getAccountNonce(accountId)
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedDepositIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function _withdrawOrder(
        uint256 accountId,
        address user,
        uint256 userPK,
        address to,
        address asset,
        uint256 shares
    ) internal view returns (SignedWithdrawIntent memory) {
        WithdrawIntent memory intent = WithdrawIntent({
            withdraw: WithdrawOrder({
                accountId: accountId,
                to: to,
                asset: asset,
                shares: shares,
                deadline: block.timestamp + 1000,
                minAmountOut: 0
            }),
            chaindId: block.chainid,
            relayerTip: 0,
            nonce: periphery.getAccountNonce(accountId)
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedWithdrawIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function test_deposit_withdraw_all_WITH_FEE()
        public
        approveAll(alice)
        approveAll(bob)
    {
        vm.startPrank(address(fund));
        periphery.openAccount(alice, block.timestamp * 2, Role.USER);
        periphery.openAccount(bob, block.timestamp * 2, Role.USER);
        vm.stopPrank();

        uint256 feeBps = 1000;

        vm.prank(address(fund));
        periphery.setFeeBps(feeBps);

        mockToken1.mint(alice, 10 * mock1Unit);

        /// alice deposits 10
        vm.prank(relayer);
        periphery.deposit(_depositOrder(1, alice, alicePK, address(mockToken1), 10 * mock1Unit));

        assertEq(periphery.vault().balanceOf(feeRecipient), 0);

        assertEq(periphery.highWaterMarkPrice(), 0);

        /// simulate that the fund gains 40 units of mockToken1
        mockToken1.mint(address(fund), 40 * mock1Unit);

        assertEq(periphery.vault().balanceOf(feeRecipient), 0);

        address claimer = makeAddr("Claimer");

        assertEq(mockToken1.balanceOf(address(fund)), 50 * mock1Unit);

        /// alice withdraws everything she is owed
        vm.prank(relayer);
        periphery.withdraw(_withdrawOrder(1, alice, alicePK, claimer, address(mockToken1), 0));

        assertApproxEqRel(mockToken1.balanceOf(address(fund)), 4 * mock1Unit, 0.1e18);

        vm.startPrank(feeRecipient);
        periphery.vault().transfer(bob, periphery.vault().balanceOf(feeRecipient));
        vm.stopPrank();

        vm.prank(relayer);
        periphery.withdraw(_withdrawOrder(2, bob, bobPK, feeRecipient, address(mockToken1), 0));

        /// @notice you wont get exact amount out because of vault inflation attack protection
        assertApproxEqRel(mockToken1.balanceOf(claimer), 46 * mock1Unit, 0.1e18);
        // assertApproxEqRel(mockToken1.balanceOf(feeRecipient), 4 * mock1Unit, 0.1e18);
        // assertEq(mockToken1.balanceOf(address(fund)), 9);

        // assertEq(periphery.vault().balanceOf(feeRecipient), 0);
        // assertEq(periphery.vault().balanceOf(alice), 0);
        // assertEq(mockToken1.balanceOf(address(fund)), periphery.vault().totalAssets());
    }

    function test_multi_user_withdraw_all_with_profit_NO_FEE()
        public
        approveAll(alice)
        approveAll(bob)
    {
        vm.startPrank(address(fund));
        periphery.openAccount(alice, block.timestamp * 2, Role.USER);
        periphery.openAccount(bob, block.timestamp * 2, Role.USER);
        vm.stopPrank();

        mockToken1.mint(alice, 10 * mock1Unit);
        mockToken1.mint(bob, 10 * mock1Unit);

        vm.startPrank(relayer);
        periphery.deposit(_depositOrder(1, alice, alicePK, address(mockToken1), 10 * mock1Unit));
        periphery.deposit(_depositOrder(2, bob, bobPK, address(mockToken1), 0));
        vm.stopPrank();

        /// simulate that the fund gains 100 units of mockToken1
        mockToken1.mint(address(fund), 100 * mock1Unit);

        vm.startPrank(relayer);
        periphery.withdraw(_withdrawOrder(1, alice, alicePK, alice, address(mockToken1), 0));
        periphery.withdraw(_withdrawOrder(2, bob, bobPK, bob, address(mockToken1), 0));
        vm.stopPrank();

        /// @notice you wont get exact amount out because of vault inflation attack protection
        assertApproxEqRel(mockToken1.balanceOf(alice), 60 * mock1Unit, 0.1e18);
        assertApproxEqRel(mockToken1.balanceOf(bob), 60 * mock1Unit, 0.1e18);
        assertApproxEqRel(mockToken1.balanceOf(address(fund)), 5, 1);
        assertEq(mockToken1.balanceOf(address(fund)), periphery.vault().totalAssets());
    }

    // function test_multi_user_withdraw_all_with_profit_WITH_FEE()
    //     public
    //     approveAll(alice)
    //     approveAll(bob)
    //     approveAll(feeRecipient)
    // {
    //     uint256 feeBps = 1000;

    //     vm.prank(address(fund));
    //     periphery.setFeeBps(feeBps);

    //     mockToken1.mint(alice, 10 * mock1Unit);
    //     mockToken1.mint(bob, 10 * mock1Unit);

    //     vm.startPrank(relayer);
    //     periphery.deposit(_depositOrder(alice, alicePK, address(mockToken1), 10 * mock1Unit));
    //     periphery.deposit(_depositOrder(bob, bobPK, address(mockToken1), 0));
    //     vm.stopPrank();

    //     assertEq(mockToken1.balanceOf(address(fund)), 20 * mock1Unit);

    //     /// simulate that the fund gains 100 units of mockToken1
    //     mockToken1.mint(address(fund), 100 * mock1Unit);

    //     assertEq(mockToken1.balanceOf(address(fund)), 120 * mock1Unit);

    //     address claimer = makeAddr("Claimer");

    //     vm.startPrank(relayer);
    //     periphery.withdraw(_withdrawOrder(alice, alicePK, claimer, address(mockToken1), 0));
    //     periphery.withdraw(_withdrawOrder(bob, bobPK, bob, address(mockToken1), 0));
    //     vm.stopPrank();

    //     vm.prank(feeRecipient);
    //     periphery.withdrawFees(address(mockToken1), 0, 0);

    //     /// @notice you wont get exact amount out because of vault inflation attack protection
    //     assertApproxEqRel(mockToken1.balanceOf(alice), 0, 0.1e18);
    //     assertApproxEqRel(mockToken1.balanceOf(bob), 55 * mock1Unit, 0.1e18);
    //     assertApproxEqRel(mockToken1.balanceOf(claimer), 55 * mock1Unit, 0.1e18);
    //     assertApproxEqRel(mockToken1.balanceOf(feeRecipient), 10 * mock1Unit, 0.1e18);
    //     assertEq(mockToken1.balanceOf(address(fund)), periphery.vault().totalAssets());
    // }

    // function test_multi_user_withdraw_all_with_loss_NO_FEE()
    //     public
    //     approveAll(alice)
    //     approveAll(bob)
    // {
    //     mockToken1.mint(alice, 10 * mock1Unit);
    //     mockToken1.mint(bob, 10 * mock1Unit);

    //     vm.startPrank(relayer);
    //     periphery.deposit(_depositOrder(alice, alicePK, address(mockToken1), 10 * mock1Unit));
    //     periphery.deposit(_depositOrder(bob, bobPK, address(mockToken1), 10 * mock1Unit));
    //     vm.stopPrank();

    //     /// simulate that the fund loses 10 units of mockToken1
    //     vm.prank(address(fund));
    //     mockToken1.transfer(address(123455), 10 * mock1Unit);

    //     vm.startPrank(relayer);
    //     periphery.withdraw(_withdrawOrder(alice, alicePK, alice, address(mockToken1), 0));
    //     periphery.withdraw(_withdrawOrder(bob, bobPK, bob, address(mockToken1), 0));
    //     vm.stopPrank();

    //     /// @notice you wont get exact amount out because of vault inflation attack protection
    //     assertApproxEqRel(mockToken1.balanceOf(alice), 5 * mock1Unit, 0.1e18);
    //     assertApproxEqRel(mockToken1.balanceOf(bob), 5 * mock1Unit, 0.1e18);
    //     assertEq(mockToken1.balanceOf(address(fund)), periphery.vault().totalAssets());
    // }

    // function test_deposit_and_partial_withdraw_WITH_FEE()
    //     public
    //     approveAll(alice)
    //     approveAll(feeRecipient)
    // {
    //     uint256 feeBps = 1000;

    //     vm.prank(address(fund));
    //     periphery.setFeeBps(feeBps);

    //     mockToken1.mint(alice, 20 * mock1Unit);

    //     vm.prank(relayer);
    //     periphery.deposit(_depositOrder(alice, alicePK, address(mockToken1), 10 * mock1Unit));

    //     /// simulate that the fund gains 10 units of mockToken1
    //     mockToken1.mint(address(fund), 10 * mock1Unit);

    //     vm.prank(relayer);
    //     periphery.deposit(_depositOrder(alice, alicePK, address(mockToken1), 10 * mock1Unit));

    //     address claimer = makeAddr("Claimer");

    //     assertEq(mockToken1.balanceOf(address(fund)), 30 * mock1Unit);

    //     uint256 aliceBalance = periphery.vault().balanceOf(alice);

    //     vm.prank(relayer);
    //     periphery.withdraw(
    //         _withdrawOrder(alice, alicePK, claimer, address(mockToken1), aliceBalance / 2)
    //     );

    //     vm.prank(feeRecipient);
    //     periphery.withdrawFees(address(mockToken1), 0, 0);

    //     /// @notice you wont get exact amount out because of vault inflation attack protection
    //     assertApproxEqRel(mockToken1.balanceOf(claimer), 15 * mock1Unit, 0.1e18);
    //     assertApproxEqRel(mockToken1.balanceOf(feeRecipient), 1 * mock1Unit, 0.1e18);
    //     assertApproxEqRel(mockToken1.balanceOf(address(fund)), ((30 / 2) - 1) * mock1Unit, 0.1e18);
    //     assertEq(mockToken1.balanceOf(address(fund)), periphery.vault().totalAssets());
    // }
}
