// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {Periphery} from "@src/modules/deposit/Periphery.sol";
import {BalanceOfOracle} from "@src/oracles/BalanceOfOracle.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";
import {MessageHashUtils} from "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import {SignedMath} from "@openzeppelin-contracts/utils/math/SignedMath.sol";
import {console2} from "@forge-std/Test.sol";
import "@src/libs/Constants.sol";
import "@src/modules/deposit/Structs.sol";
import {ModuleProxyFactory} from "@zodiac/factory/ModuleProxyFactory.sol";
import {DeployPermit2} from "@permit2/test/utils/DeployPermit2.sol";
import {IPermit2} from "@permit2/src/interfaces/IPermit2.sol";
import {IEIP712} from "@permit2/src/interfaces/IEIP712.sol";
import "@permit2/src/interfaces/IAllowanceTransfer.sol";
import "@permit2/src/libraries/PermitHash.sol";
import {IERC20Permit} from "@openzeppelin-contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@src/modules/deposit/DepositModule.sol";

uint8 constant VALUATION_DECIMALS = 18;
uint256 constant VAULT_DECIMAL_OFFSET = 1;
uint256 constant MINIMUM_DEPOSIT = 1000;
uint256 constant MINIMUM_WITHDRAWAL = 1000;

abstract contract TestBaseDeposit is TestBaseGnosis, DeployPermit2 {
    using MessageHashUtils for bytes;
    using SignedMath for int256;

    bytes32 internal constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    ISafe internal fund;
    EulerRouter internal oracleRouter;
    Periphery internal periphery;
    address internal peripheryMastercopy;
    DepositModule internal depositModule;
    address internal depositModuleMastercopy;
    MockERC20 internal mockToken1;
    MockERC20 internal mockToken2;

    BalanceOfOracle internal balanceOfOracle;

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
    address permit2;

    function setUp() public virtual override(TestBaseGnosis) {
        TestBaseGnosis.setUp();

        (feeRecipient, feeRecipientPK) = makeAddrAndKey("FeeRecipient");

        relayer = makeAddr("Relayer");

        (alice, alicePK) = makeAddrAndKey("Alice");

        (bob, bobPK) = makeAddrAndKey("Bob");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = ISafe(address(deploySafe(admins, 1, 1)));
        vm.label(address(fund), "Fund");

        require(address(fund).balance == 0, "Fund should not have balance");

        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

        vm.prank(address(fund));
        oracleRouter = new EulerRouter(address(1), address(fund));
        vm.label(address(oracleRouter), "OracleRouter");

        mockToken1 = new MockERC20(18);
        vm.label(address(mockToken1), "MockToken1");

        mockToken2 = new MockERC20(6);
        vm.label(address(mockToken2), "MockToken2");

        mock1Unit = 1 * 10 ** mockToken1.decimals();
        mock2Unit = 1 * 10 ** mockToken2.decimals();

        // deploy periphery using module factory
        ModuleProxyFactory factory = new ModuleProxyFactory();
        permit2 = address(deployPermit2());

        depositModuleMastercopy = address(new DepositModule());

        bytes memory depositModuleInitializer = abi.encodeWithSelector(
            DepositModule.setUp.selector,
            abi.encode("DepositModule", "DM", 18, address(fund), address(oracleRouter))
        );

        depositModule = DepositModule(
            factory.deployModule(
                depositModuleMastercopy,
                depositModuleInitializer,
                uint256(bytes32("depositModule-salt"))
            )
        );

        vm.label(address(depositModule), "DepositModule");

        vm.startPrank(address(fund));
        fund.enableModule(address(depositModule));
        vm.stopPrank();

        assertTrue(fund.isModuleEnabled(address(depositModule)), "DepositModule not module");

        peripheryMastercopy = address(new Periphery(permit2));

        bytes memory initializer = abi.encodeWithSelector(
            Periphery.setUp.selector,
            abi.encode(
                "BrokerNft",
                "bNFT",
                address(fund),
                address(fund),
                address(fund),
                address(depositModule),
                address(feeRecipient)
            )
        );

        periphery = Periphery(
            factory.deployModule(
                peripheryMastercopy, initializer, uint256(bytes32("periphery-salt"))
            )
        );

        vm.label(address(periphery), "Periphery");

        vm.startPrank(address(fund));
        periphery.grantApproval(address(mockToken1));
        periphery.grantApproval(address(mockToken2));
        periphery.grantApproval(address(depositModule.getVault()));
        depositModule.grantRole(CONTROLLER_ROLE, address(periphery));
        vm.stopPrank();

        /// @notice this much match the vault implementation
        oneUnitOfAccount =
            1 * 10 ** (depositModule.unitOfAccount().decimals() + VAULT_DECIMAL_OFFSET);

        // lets enable assets on the fund
        vm.startPrank(address(fund));
        depositModule.enableGlobalAssetPolicy(
            address(mockToken1),
            AssetPolicy({
                minimumDeposit: MINIMUM_DEPOSIT,
                minimumWithdrawal: MINIMUM_WITHDRAWAL,
                canDeposit: true,
                canWithdraw: true,
                enabled: true
            })
        );

        depositModule.enableGlobalAssetPolicy(
            address(mockToken2),
            AssetPolicy({
                minimumDeposit: MINIMUM_DEPOSIT,
                minimumWithdrawal: MINIMUM_WITHDRAWAL,
                canDeposit: true,
                canWithdraw: true,
                enabled: true
            })
        );
        vm.stopPrank();

        address unitOfAccount = address(depositModule.unitOfAccount());

        balanceOfOracle = new BalanceOfOracle(address(fund), address(oracleRouter));
        vm.label(address(balanceOfOracle), "BalanceOfOracle");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(fund), unitOfAccount, address(balanceOfOracle));

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

        vm.startPrank(address(fund));
        oracleRouter.govSetResolvedVault(depositModule.getVault(), true);
        vm.stopPrank();
    }

    function _create_permit2_single_allowance_signature(
        address token,
        uint256 amount,
        uint256 expiration,
        uint256 nonce,
        address spender,
        uint256 sigDeadline
    )
        internal
        returns (IAllowanceTransfer.PermitSingle memory permitSingle, bytes memory signature)
    {
        permitSingle = IAllowanceTransfer.PermitSingle({
            details: IAllowanceTransfer.PermitDetails({
                token: token,
                amount: uint160(amount),
                expiration: uint48(expiration),
                nonce: uint48(nonce)
            }),
            spender: spender,
            sigDeadline: sigDeadline
        });

        bytes32 theHash = PermitHash.hash(permitSingle);
        theHash =
            keccak256(abi.encodePacked("\x19\x01", IEIP712(permit2).DOMAIN_SEPARATOR(), theHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePK, theHash);
        signature = abi.encodePacked(r, s, v);
    }

    function _create_permit_signature(
        uint256 ownerPK,
        address owner,
        address asset,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        uint256 nonce = IERC20Permit(asset).nonces(owner);
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 theHash =
            MessageHashUtils.toTypedDataHash(IERC20Permit(asset).DOMAIN_SEPARATOR(), structHash);
        (v, r, s) = vm.sign(ownerPK, theHash);
    }

    function _enableBrokerAssetPolicy(
        address enabler,
        uint256 accountId,
        address asset,
        bool isDeposit
    ) internal {
        vm.startPrank(enabler);
        periphery.enableBrokerAssetPolicy(accountId, asset, isDeposit);
        vm.stopPrank();
    }

    modifier enableBrokerAssetPolicy(
        address enabler,
        uint256 accountId,
        address asset,
        bool isDeposit
    ) {
        _enableBrokerAssetPolicy(enabler, accountId, asset, isDeposit);

        _;
    }

    modifier openAccount(address user_, uint256 ttl_, bool transferable_) {
        _openAccount(user_, ttl_, transferable_);

        _;
    }

    function _openAccount(address user_, uint256 ttl_, bool transferable_) internal {
        vm.startPrank(address(fund));
        periphery.openAccount(
            CreateAccountParams({
                transferable: transferable_,
                user: user_,
                ttl: ttl_,
                shareMintLimit: type(uint256).max,
                brokerPerformanceFeeInBps: 0,
                protocolPerformanceFeeInBps: 0,
                brokerEntranceFeeInBps: 0,
                protocolEntranceFeeInBps: 0,
                brokerExitFeeInBps: 0,
                protocolExitFeeInBps: 0,
                feeRecipient: address(0)
            })
        );
        vm.stopPrank();
    }

    modifier approveAllPeriphery(address user) {
        vm.startPrank(user);
        mockToken1.approve(address(periphery), type(uint256).max);
        mockToken2.approve(address(periphery), type(uint256).max);
        depositModule.internalVault().approve(address(periphery), type(uint256).max);
        vm.stopPrank();

        _;
    }

    modifier approvePermit2(address user) {
        vm.startPrank(user);
        mockToken1.approve(permit2, type(uint256).max);
        mockToken2.approve(permit2, type(uint256).max);
        depositModule.internalVault().approve(permit2, type(uint256).max);
        vm.stopPrank();

        _;
    }

    function depositOrder(uint256 accountId, address user, address token, uint256 amount)
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
            minSharesOut: 0,
            referralCode: 0
        });
    }

    function unsignedDepositIntent(
        uint256 accountId,
        address user,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 relayerTip,
        uint256 bribe
    ) internal view returns (DepositIntent memory) {
        return DepositIntent({
            deposit: DepositOrder({
                accountId: accountId,
                recipient: user,
                asset: token,
                amount: amount,
                deadline: block.timestamp + 1000,
                minSharesOut: 0,
                referralCode: 0
            }),
            chaindId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: nonce
        });
    }

    function depositIntent(
        uint256 accountId,
        address user,
        uint256 userPK,
        address token,
        uint256 amount,
        uint256 relayerTip,
        uint256 bribe,
        uint256 nonce
    ) internal view returns (SignedDepositIntent memory) {
        DepositIntent memory intent = DepositIntent({
            deposit: depositOrder(accountId, user, token, amount),
            chaindId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: nonce
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedDepositIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function withdrawOrder(uint256 accountId, address to, address asset, uint256 shares)
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
            minAmountOut: 0,
            referralCode: 0
        });
    }

    function unsignedWithdrawIntent(
        uint256 accountId,
        address to,
        address asset,
        uint256 shares,
        uint256 nonce,
        uint256 relayerTip,
        uint256 bribe
    ) internal view returns (WithdrawIntent memory) {
        return WithdrawIntent({
            withdraw: WithdrawOrder({
                accountId: accountId,
                to: to,
                asset: asset,
                shares: shares,
                deadline: block.timestamp + 1000,
                minAmountOut: 0,
                referralCode: 0
            }),
            chaindId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: nonce
        });
    }

    function signedWithdrawIntent(
        uint256 accountId,
        address to,
        uint256 userPK,
        address asset,
        uint256 shares,
        uint256 relayerTip,
        uint256 bribe,
        uint256 nonce
    ) internal view returns (SignedWithdrawIntent memory) {
        WithdrawIntent memory intent = WithdrawIntent({
            withdraw: withdrawOrder(accountId, to, asset, shares),
            chaindId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: nonce
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedWithdrawIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function signdepositIntent(DepositIntent memory intent, uint256 userPK)
        internal
        pure
        returns (SignedDepositIntent memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedDepositIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function signsignedWithdrawIntent(WithdrawIntent memory intent, uint256 userPK)
        internal
        pure
        returns (SignedWithdrawIntent memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, abi.encode(intent).toEthSignedMessageHash());

        return SignedWithdrawIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }
}
