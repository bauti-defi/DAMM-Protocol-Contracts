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
import "@src/libs/Errors.sol";

uint8 constant VALUATION_DECIMALS = 18;
uint256 constant VAULT_DECIMAL_OFFSET = 1;

contract TestDepositPermissions is TestBaseFund, TestBaseProtocol {
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
                        feeRecipient,
                        true
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
                permissioned: true,
                enabled: true
            })
        );
        vm.stopPrank();

        address unitOfAccount = address(periphery.unitOfAccount());

        FundValuationOracle fundValuationOracle = new FundValuationOracle(address(oracleRouter));
        vm.label(address(fundValuationOracle), "FundValuationOracle");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(fund), unitOfAccount, address(fundValuationOracle));

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

        mockToken1.mint(alice, 100_000_000 * mock1Unit);
    }

    modifier whitelistUser(address user, Role role) {
        vm.startPrank(address(fund));
        periphery.openAccount(user, role);
        vm.stopPrank();

        _;
    }

    function _depositIntent(address user, address token, uint256 amount, uint256 nonce)
        internal
        view
        returns (DepositIntent memory)
    {
        return DepositIntent({
            order: DepositOrder({
                recipient: user,
                asset: token,
                amount: amount,
                deadline: block.timestamp + 1000,
                minSharesOut: 0
            }),
            user: user,
            chaindId: block.chainid,
            relayerTip: 0,
            nonce: nonce
        });
    }

    function _signDepositIntent(DepositIntent memory intent, uint256 userPK)
        internal
        pure
        returns (SignedDepositOrder memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedDepositOrder({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function _withdrawIntent(address user, address to, address asset, uint256 shares, uint256 nonce)
        internal
        view
        returns (WithdrawIntent memory)
    {
        return WithdrawIntent({
            user: user,
            to: to,
            asset: asset,
            chaindId: block.chainid,
            shares: shares,
            minAmountOut: 0,
            deadline: block.timestamp + 1000,
            relayerTip: 0,
            nonce: nonce
        });
    }

    function _signWithdrawIntent(WithdrawIntent memory intent, uint256 userPK)
        internal
        pure
        returns (WithdrawOrder memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return WithdrawOrder({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function test_only_enabled_account_can_deposit_withdraw() public {
        SignedDepositOrder memory dOrder =
            _signDepositIntent(_depositIntent(alice, address(mockToken1), mock1Unit, 0), alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OnlyUser.selector);
        periphery.deposit(dOrder);

        WithdrawOrder memory wOrder = _signWithdrawIntent(
            _withdrawIntent(alice, alice, address(mockToken1), mock1Unit, 0), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OnlyUser.selector);
        periphery.withdraw(wOrder);
    }

    function test_order_must_have_valid_nonce() public whitelistUser(alice, Role.USER) {
        SignedDepositOrder memory dOrder =
            _signDepositIntent(_depositIntent(alice, address(mockToken1), mock1Unit, 1000), alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidNonce.selector);
        periphery.deposit(dOrder);

        WithdrawOrder memory wOrder = _signWithdrawIntent(
            _withdrawIntent(alice, alice, address(mockToken1), mock1Unit, 10000), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidNonce.selector);
        periphery.withdraw(wOrder);
    }

    function test_order_must_be_within_deadline() public whitelistUser(alice, Role.USER) {
        SignedDepositOrder memory dOrder =
            _signDepositIntent(_depositIntent(alice, address(mockToken1), mock1Unit, 0), alicePK);

        // increase timestamp
        vm.warp(100000000);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_IntentExpired.selector);
        periphery.deposit(dOrder);

        // reset timestamp to generate valid order
        vm.warp(0);

        WithdrawOrder memory wOrder = _signWithdrawIntent(
            _withdrawIntent(alice, alice, address(mockToken1), mock1Unit, 0), alicePK
        );

        // increase timestamp
        vm.warp(100000000);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_IntentExpired.selector);
        periphery.withdraw(wOrder);
    }

    function test_order_chain_id_must_match() public whitelistUser(alice, Role.USER) {
        DepositIntent memory dIntent = _depositIntent(alice, address(mockToken1), mock1Unit, 0);

        dIntent.chaindId = 1000;

        SignedDepositOrder memory dOrder = _signDepositIntent(dIntent, alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidChain.selector);
        periphery.deposit(dOrder);

        WithdrawIntent memory wIntent =
            _withdrawIntent(alice, alice, address(mockToken1), mock1Unit, 0);

        wIntent.chaindId = 1000;

        WithdrawOrder memory wOrder = _signWithdrawIntent(wIntent, alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidChain.selector);
        periphery.withdraw(wOrder);
    }

    function test_only_super_user_can_deposit_or_withdraw_permissioned_asset()
        public
        whitelistUser(bob, Role.SUPER_USER)
        whitelistUser(alice, Role.USER)
    {
        mockToken2.mint(bob, 100_000_000 * mock2Unit);
        mockToken2.mint(alice, 100_000_000 * mock2Unit);

        vm.startPrank(alice);
        mockToken2.approve(address(periphery), type(uint256).max);
        periphery.vault().approve(address(periphery), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        mockToken2.approve(address(periphery), type(uint256).max);
        periphery.vault().approve(address(periphery), type(uint256).max);
        vm.stopPrank();

        SignedDepositOrder memory dOrder = _signDepositIntent(
            _depositIntent(alice, address(mockToken2), 1 * mock2Unit, 0), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OnlySuperUser.selector);
        periphery.deposit(dOrder);

        dOrder =
            _signDepositIntent(_depositIntent(bob, address(mockToken2), 10 * mock2Unit, 0), bobPK);

        vm.prank(relayer);
        periphery.deposit(dOrder);

        WithdrawOrder memory wOrder =
            _signWithdrawIntent(_withdrawIntent(bob, bob, address(mockToken2), 0, 1), bobPK);

        vm.prank(relayer);
        periphery.withdraw(wOrder);

        wOrder =
            _signWithdrawIntent(_withdrawIntent(alice, alice, address(mockToken2), 0, 0), alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OnlySuperUser.selector);
        periphery.withdraw(wOrder);
    }
}
