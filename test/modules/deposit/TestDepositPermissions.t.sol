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

    modifier approveAll(address user) {
        vm.startPrank(user);
        mockToken1.approve(address(periphery), type(uint256).max);
        periphery.vault().approve(address(periphery), type(uint256).max);
        vm.stopPrank();

        _;
    }

    modifier whitelistUser(address user_, uint256 ttl_, Role role_) {
        vm.startPrank(address(fund));
        periphery.openAccount(
            CreateAccountParams({
                transferable: false,
                user: user_,
                role: role_,
                ttl: ttl_,
                shareMintLimit: type(uint256).max,
                brokerPerformanceFeeInBps: 0
            })
        );
        vm.stopPrank();

        _;
    }

    function _depositIntent(
        uint256 accountId,
        address user,
        address token,
        uint256 amount,
        uint256 nonce
    ) internal view returns (DepositIntent memory) {
        return DepositIntent({
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
            bribe: 0,
            nonce: nonce
        });
    }

    function _signDepositIntent(DepositIntent memory intent, uint256 userPK)
        internal
        pure
        returns (SignedDepositIntent memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedDepositIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function _withdrawIntent(
        uint256 accountId,
        address user,
        address to,
        address asset,
        uint256 shares,
        uint256 nonce
    ) internal view returns (WithdrawIntent memory) {
        return WithdrawIntent({
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
            bribe: 0,
            nonce: nonce
        });
    }

    function _signWithdrawIntent(WithdrawIntent memory intent, uint256 userPK)
        internal
        pure
        returns (SignedWithdrawIntent memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedWithdrawIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function test_only_account_signature_is_valid(string memory name)
        public
        whitelistUser(alice, 10000, Role.USER)
    {
        (address user, uint256 userPK) = makeAddrAndKey(name);

        SignedDepositIntent memory dOrder =
            _signDepositIntent(_depositIntent(1, alice, address(mockToken1), mock1Unit, 0), userPK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidSignature.selector);
        periphery.deposit(dOrder);

        SignedWithdrawIntent memory wOrder = _signWithdrawIntent(
            _withdrawIntent(1, alice, alice, address(mockToken1), mock1Unit, 0), userPK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidSignature.selector);
        periphery.withdraw(wOrder);
    }

    function test_only_enabled_account_can_deposit_withdraw(uint256 accountId_) public {
        SignedDepositIntent memory dOrder = _signDepositIntent(
            _depositIntent(accountId_, alice, address(mockToken1), mock1Unit, 0), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountDoesNotExist.selector);
        periphery.deposit(dOrder);

        SignedWithdrawIntent memory wOrder = _signWithdrawIntent(
            _withdrawIntent(accountId_, alice, alice, address(mockToken1), mock1Unit, 0), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountDoesNotExist.selector);
        periphery.withdraw(wOrder);
    }

    function test_only_active_account_can_deposit_withdraw()
        public
        whitelistUser(alice, 100000, Role.USER)
    {
        vm.prank(address(fund));
        periphery.pauseAccount(1);

        SignedDepositIntent memory dOrder =
            _signDepositIntent(_depositIntent(1, alice, address(mockToken1), mock1Unit, 0), alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountNotActive.selector);
        periphery.deposit(dOrder);

        SignedWithdrawIntent memory wOrder = _signWithdrawIntent(
            _withdrawIntent(1, alice, alice, address(mockToken1), mock1Unit, 0), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountNotActive.selector);
        periphery.withdraw(wOrder);
    }

    function test_order_must_have_valid_nonce(uint256 nonce_)
        public
        whitelistUser(alice, 1000000, Role.USER)
    {
        vm.assume(nonce_ > 1);

        SignedDepositIntent memory dOrder = _signDepositIntent(
            _depositIntent(1, alice, address(mockToken1), mock1Unit, nonce_), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidNonce.selector);
        periphery.deposit(dOrder);

        SignedWithdrawIntent memory wOrder = _signWithdrawIntent(
            _withdrawIntent(1, alice, alice, address(mockToken1), mock1Unit, nonce_), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidNonce.selector);
        periphery.withdraw(wOrder);
    }

    function test_order_must_be_within_deadline(uint256 timestamp_)
        public
        whitelistUser(alice, 100000000 * 2, Role.USER)
    {
        vm.assume(timestamp_ > 10000);
        vm.assume(timestamp_ < 100000000 * 2);

        SignedDepositIntent memory dOrder =
            _signDepositIntent(_depositIntent(1, alice, address(mockToken1), mock1Unit, 0), alicePK);

        // increase timestamp
        vm.warp(timestamp_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OrderExpired.selector);
        periphery.deposit(dOrder);

        // reset timestamp to generate valid order
        vm.warp(0);

        SignedWithdrawIntent memory wOrder = _signWithdrawIntent(
            _withdrawIntent(1, alice, alice, address(mockToken1), mock1Unit, 0), alicePK
        );

        // increase timestamp
        vm.warp(timestamp_);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OrderExpired.selector);
        periphery.withdraw(wOrder);
    }

    function test_order_chain_id_must_match(uint256 chainId_)
        public
        whitelistUser(alice, 1000000, Role.USER)
    {
        vm.assume(chainId_ != block.chainid);

        DepositIntent memory dIntent = _depositIntent(1, alice, address(mockToken1), mock1Unit, 0);

        dIntent.chaindId = chainId_;

        SignedDepositIntent memory dOrder = _signDepositIntent(dIntent, alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidChain.selector);
        periphery.deposit(dOrder);

        WithdrawIntent memory wIntent =
            _withdrawIntent(1, alice, alice, address(mockToken1), mock1Unit, 0);

        wIntent.chaindId = chainId_;

        SignedWithdrawIntent memory wOrder = _signWithdrawIntent(wIntent, alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_InvalidChain.selector);
        periphery.withdraw(wOrder);
    }

    function test_only_super_user_can_deposit_or_withdraw_permissioned_asset()
        public
        whitelistUser(alice, 1000000 * 2, Role.USER)
        whitelistUser(bob, 1000000 * 2, Role.SUPER_USER)
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

        SignedDepositIntent memory dOrder = _signDepositIntent(
            _depositIntent(1, alice, address(mockToken2), 1 * mock2Unit, 0), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OnlySuperUser.selector);
        periphery.deposit(dOrder);

        dOrder = _signDepositIntent(
            _depositIntent(2, bob, address(mockToken2), 10 * mock2Unit, 0), bobPK
        );

        vm.prank(relayer);
        periphery.deposit(dOrder);

        SignedWithdrawIntent memory wOrder = _signWithdrawIntent(
            _withdrawIntent(2, bob, bob, address(mockToken2), type(uint256).max, 1), bobPK
        );

        vm.prank(relayer);
        periphery.withdraw(wOrder);

        wOrder = _signWithdrawIntent(
            _withdrawIntent(1, alice, alice, address(mockToken2), type(uint256).max, 0), alicePK
        );

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_OnlySuperUser.selector);
        periphery.withdraw(wOrder);
    }

    function test_only_non_expired_account_can_deposit(uint256 timestamp)
        public
        whitelistUser(alice, 1, Role.USER)
        approveAll(alice)
    {
        vm.assume(timestamp > 1);
        vm.assume(timestamp < 100000000 * 2);

        vm.warp(timestamp);

        SignedDepositIntent memory dOrder =
            _signDepositIntent(_depositIntent(1, alice, address(mockToken1), mock1Unit, 0), alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AccountExpired.selector);
        periphery.deposit(dOrder);
    }

    function test_expired_account_can_withdraw()
        public
        whitelistUser(alice, 1000, Role.USER)
        approveAll(alice)
    {
        SignedDepositIntent memory dOrder =
            _signDepositIntent(_depositIntent(1, alice, address(mockToken1), mock1Unit, 0), alicePK);

        vm.prank(relayer);
        periphery.deposit(dOrder);

        assertTrue(periphery.vault().balanceOf(alice) > 0);
        assertFalse(periphery.getAccountInfo(1).isExpired());

        vm.warp(100000000 * 2);

        assertTrue(periphery.getAccountInfo(1).isExpired());

        SignedWithdrawIntent memory wOrder = _signWithdrawIntent(
            _withdrawIntent(1, alice, alice, address(mockToken1), type(uint256).max, 1), alicePK
        );

        vm.prank(relayer);
        periphery.withdraw(wOrder);

        assertTrue(periphery.vault().balanceOf(alice) == 0);
    }

    function test_only_allowed_assets_can_be_deposited_or_withdrawn(address asset)
        public
        whitelistUser(alice, 1000000, Role.USER)
    {
        vm.assume(asset != address(mockToken1));
        vm.assume(asset != address(mockToken2));

        SignedDepositIntent memory dOrder =
            _signDepositIntent(_depositIntent(1, alice, asset, mock2Unit, 0), alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.deposit(dOrder);

        SignedWithdrawIntent memory wOrder =
            _signWithdrawIntent(_withdrawIntent(1, alice, alice, asset, mock2Unit, 0), alicePK);

        vm.prank(relayer);
        vm.expectRevert(Errors.Deposit_AssetUnavailable.selector);
        periphery.withdraw(wOrder);
    }

    function test_only_admin_can_pause_unpause_account(address attacker)
        public
        whitelistUser(alice, 1000000, Role.USER)
    {
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyAdmin.selector);
        periphery.pauseAccount(1);

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyAdmin.selector);
        periphery.unpauseAccount(1);

        vm.prank(address(fund));
        periphery.pauseAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.PAUSED);

        vm.prank(address(fund));
        periphery.unpauseAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.ACTIVE);
    }

    function test_only_admin_can_close_account(address attacker)
        public
        whitelistUser(alice, 1000000, Role.USER)
    {
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyAdmin.selector);
        periphery.closeAccount(1);

        vm.prank(address(fund));
        periphery.closeAccount(1);

        assertTrue(periphery.getAccountInfo(1).state == AccountState.CLOSED);
        vm.expectRevert();
        periphery.ownerOf(1);
    }

    function test_only_fund_can_pause_unpause_module(address attacker) public {
        vm.assume(attacker != address(fund));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
        periphery.pause();

        vm.prank(address(fund));
        periphery.pause();

        assertTrue(periphery.paused());

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
        periphery.unpause();

        vm.prank(address(fund));
        periphery.unpause();

        assertTrue(!periphery.paused());
    }

    function test_only_fund_can_transfer_account_nft(address attacker)
        public
        whitelistUser(alice, 1000000, Role.USER)
    {
        vm.prank(attacker);
        vm.expectRevert(Errors.Deposit_AccountNotTransferable.selector);
        periphery.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(Errors.Deposit_AccountNotTransferable.selector);
        periphery.transferFrom(alice, bob, 1);

        vm.prank(attacker);
        vm.expectRevert(Errors.Deposit_AccountNotTransferable.selector);
        periphery.safeTransferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(Errors.Deposit_AccountNotTransferable.selector);
        periphery.safeTransferFrom(alice, bob, 1);
    }

    function test_only_fund_can_change_admin(address attacker) public {
        vm.assume(attacker != address(fund) && attacker != address(0));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
        periphery.setAdmin(attacker);

        vm.prank(address(fund));
        periphery.setAdmin(attacker);

        assertTrue(periphery.admin() == attacker);
    }

    function test_only_fund_can_change_fee_recipient(address attacker) public {
        vm.assume(attacker != address(fund) && attacker != address(0));

        vm.prank(attacker);
        vm.expectRevert(Errors.OnlyFund.selector);
        periphery.setFeeRecipient(attacker);

        vm.prank(address(fund));
        periphery.setFeeRecipient(attacker);

        assertTrue(periphery.feeRecipient() == attacker);
    }

    /// TODO: test share mint limit exceeded
}
