// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TestBaseFund} from "@test/base/TestBaseFund.sol";
import {TestBaseProtocol} from "@test/base/TestBaseProtocol.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {Periphery} from "@src/modules/deposit/Periphery.sol";
import {FundValuationOracle} from "@src/oracles/FundValuationOracle.sol";
import "@src/modules/deposit/Structs.sol";
import {NATIVE_ASSET} from "@src/libs/Constants.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/math/SignedMath.sol";
import {console2} from "@forge-std/Test.sol";

uint8 constant VALUATION_DECIMALS = 18;
uint256 constant VAULT_DECIMAL_OFFSET = 1;

uint256 constant MAX_NET_EXIT_FEE_IN_BPS = 5_000;
uint256 constant MAX_NET_PERFORMANCE_FEE_IN_BPS = 7_000;

contract TestDepositWithdraw is TestBaseFund, TestBaseProtocol {
    using MessageHashUtils for bytes;
    using SignedMath for int256;

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

        fund =
            fundFactory.deployFund(address(safeProxyFactory), address(safeSingleton), admins, 1, 1);
        vm.label(address(fund), "Fund");

        require(address(fund).balance == 0, "Fund should not have balance");

        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

        vm.prank(address(fund));
        oracleRouter = new EulerRouter(address(1), address(fund));
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

    function _depositOrder(uint256 accountId, address user, address token, uint256 amount)
        internal
        view
        returns (DepositOrder memory)
    {
        return DepositOrder({
            accountId: accountId,
            recipient: user,
            asset: token,
            amount: amount,
            deadline: block.timestamp + 1000,
            minSharesOut: 0
        });
    }

    function _depositIntent(
        uint256 accountId,
        address user,
        uint256 userPK,
        address token,
        uint256 amount,
        uint256 relayerTip,
        uint256 bribe
    ) internal view returns (SignedDepositIntent memory) {
        DepositIntent memory intent = DepositIntent({
            deposit: _depositOrder(accountId, user, token, amount),
            chaindId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: periphery.getAccountNonce(accountId)
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedDepositIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function _withdrawOrder(uint256 accountId, address to, address asset, uint256 shares)
        internal
        view
        returns (WithdrawOrder memory)
    {
        return WithdrawOrder({
            accountId: accountId,
            to: to,
            asset: asset,
            shares: shares,
            deadline: block.timestamp + 1000,
            minAmountOut: 0
        });
    }

    function _withdrawIntent(
        uint256 accountId,
        uint256 userPK,
        address to,
        address asset,
        uint256 shares,
        uint256 relayerTip,
        uint256 bribe
    ) internal view returns (SignedWithdrawIntent memory) {
        WithdrawIntent memory intent = WithdrawIntent({
            withdraw: _withdrawOrder(accountId, to, asset, shares),
            chaindId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: periphery.getAccountNonce(accountId)
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedWithdrawIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    struct TestParams {
        bool useIntent;
        uint32 depositAmount;
        int32 profitAmount;
        uint8 brokerPerformanceFeeInBps;
        uint8 protocolPerformanceFeeInBps;
        uint8 brokerExitFeeInBps;
        uint8 protocolExitFeeInBps;
    }

    function test_deposit_withdraw_all_WITH_FEE(TestParams memory params)
        public
        approveAll(alice)
    {
        vm.assume(params.depositAmount > 10);

        uint256 protocolExitFeeInBps = uint256(params.protocolExitFeeInBps) * 40;
        uint256 brokerExitFeeInBps = uint256(params.brokerExitFeeInBps) * 40;
        vm.assume(brokerExitFeeInBps + protocolExitFeeInBps < MAX_NET_EXIT_FEE_IN_BPS);

        uint256 brokerPerformanceFeeInBps = uint256(params.brokerPerformanceFeeInBps) * 40;
        uint256 protocolPerformanceFeeInBps = uint256(params.protocolPerformanceFeeInBps) * 40;
        vm.assume(
            protocolPerformanceFeeInBps + brokerPerformanceFeeInBps < MAX_NET_PERFORMANCE_FEE_IN_BPS
        );

        /// @notice we cast to uint256 because we want to test the max values
        uint256 depositAmount = params.depositAmount * mock1Unit;
        int256 profitAmount = params.profitAmount * int256(mock1Unit);

        vm.assume(profitAmount.abs() > 1 * mock1Unit || profitAmount == 0);
        vm.assume(profitAmount.abs() < depositAmount);

        vm.startPrank(address(fund));
        periphery.openAccount(
            CreateAccountParams({
                transferable: false,
                user: alice,
                role: Role.USER,
                ttl: 100000000,
                shareMintLimit: type(uint256).max,
                brokerPerformanceFeeInBps: brokerPerformanceFeeInBps,
                protocolPerformanceFeeInBps: protocolPerformanceFeeInBps,
                brokerEntranceFeeInBps: 0,
                protocolEntranceFeeInBps: 0,
                brokerExitFeeInBps: brokerExitFeeInBps,
                protocolExitFeeInBps: protocolExitFeeInBps
            })
        );
        vm.stopPrank();

        mockToken1.mint(alice, depositAmount);

        /// alice deposits
        if (params.useIntent) {
            periphery.deposit(
                _depositIntent(1, alice, alicePK, address(mockToken1), type(uint256).max, 0, 0)
            );
        } else {
            vm.prank(alice);
            periphery.deposit(_depositOrder(1, alice, address(mockToken1), type(uint256).max));
        }

        /// simulate that the fund makes profit or loses money
        if (profitAmount > 0) {
            mockToken1.mint(address(fund), profitAmount.abs());
        } else {
            vm.prank(address(fund));
            mockToken1.transfer(address(1), profitAmount.abs());
        }

        address claimer = makeAddr("Claimer");

        uint256 exitFeeForBroker = brokerExitFeeInBps > 0
            ? mockToken1.balanceOf(address(fund)) * brokerExitFeeInBps / 10_000
            : 0;
        uint256 exitFeeForProtocol = protocolExitFeeInBps > 0
            ? mockToken1.balanceOf(address(fund)) * protocolExitFeeInBps / 10_000
            : 0;

        if (params.useIntent) {
            periphery.withdraw(
                _withdrawIntent(1, alicePK, claimer, address(mockToken1), type(uint256).max, 0, 0)
            );
        } else {
            vm.prank(alice);
            periphery.withdraw(_withdrawOrder(1, claimer, address(mockToken1), type(uint256).max));
        }

        uint256 performanceFeeForBroker = brokerPerformanceFeeInBps > 0 && profitAmount > 0
            ? profitAmount.abs() * brokerPerformanceFeeInBps / 10_000
            : 0;
        uint256 performanceFeeForProtocol = protocolPerformanceFeeInBps > 0 && profitAmount > 0
            ? profitAmount.abs() * protocolPerformanceFeeInBps / 10_000
            : 0;

        uint256 profit = profitAmount.abs() - performanceFeeForBroker - performanceFeeForProtocol;

        /// @notice you wont get exact amount out because of vault inflation attack protection
        if (profitAmount > 0) {
            assertApproxEqRel(
                mockToken1.balanceOf(claimer),
                depositAmount + profit - exitFeeForBroker - exitFeeForProtocol,
                0.1e18,
                "Claimer balance wrong"
            );
            assertApproxEqRel(
                mockToken1.balanceOf(alice),
                performanceFeeForBroker + exitFeeForBroker,
                0.1e18,
                "broker fee wrong"
            );
            assertApproxEqRel(
                mockToken1.balanceOf(feeRecipient),
                performanceFeeForProtocol + exitFeeForProtocol,
                0.1e18,
                "protocol fee wrong"
            );
        } else {
            assertEq(
                mockToken1.balanceOf(claimer),
                depositAmount - profitAmount.abs() - exitFeeForBroker - exitFeeForProtocol
            );
            assertEq(mockToken1.balanceOf(alice), exitFeeForBroker);
            assertEq(mockToken1.balanceOf(feeRecipient), exitFeeForProtocol);
        }

        assertEq(periphery.vault().balanceOf(alice), 0);
        assertEq(mockToken1.balanceOf(address(fund)), periphery.vault().totalAssets());
    }
}
