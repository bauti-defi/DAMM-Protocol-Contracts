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

uint8 constant VALUATION_DECIMALS = 18;
uint256 constant VAULT_DECIMAL_OFFSET = 1;
uint256 constant MINIMUM_DEPOSIT = 1000;
uint256 constant MINIMUM_WITHDRAWAL = 1000;

abstract contract TestBaseDeposit is TestBaseGnosis {
    using MessageHashUtils for bytes;
    using SignedMath for int256;

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    ISafe internal fund;
    EulerRouter internal oracleRouter;
    Periphery internal periphery;
    address internal peripheryMastercopy;
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

        // deploy periphery using module factory
        ModuleProxyFactory factory = new ModuleProxyFactory();

        peripheryMastercopy = address(new Periphery());

        bytes memory initializer = abi.encodeWithSelector(
            Periphery.setUp.selector,
            abi.encode(
                "TestVault",
                "TV",
                18,
                address(fund),
                address(oracleRouter),
                address(fund),
                address(feeRecipient)
            )
        );

        periphery = Periphery(
            factory.deployModule(
                peripheryMastercopy, initializer, uint256(bytes32("periphery-salt"))
            )
        );

        vm.startPrank(address(fund));
        fund.enableModule(address(periphery));
        vm.stopPrank();

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
        // fund.setAssetToValuate(address(mockToken1));
        periphery.enableGlobalAssetPolicy(
            address(mockToken1),
            AssetPolicy({
                minimumDeposit: MINIMUM_DEPOSIT,
                minimumWithdrawal: MINIMUM_WITHDRAWAL,
                canDeposit: true,
                canWithdraw: true,
                enabled: true
            })
        );

        // fund.setAssetToValuate(address(mockToken2));
        periphery.enableGlobalAssetPolicy(
            address(mockToken2),
            AssetPolicy({
                minimumDeposit: MINIMUM_DEPOSIT,
                minimumWithdrawal: MINIMUM_WITHDRAWAL,
                canDeposit: true,
                canWithdraw: true,
                enabled: true
            })
        );

        // native eth
        // fund.setAssetToValuate(NATIVE_ASSET);
        periphery.enableGlobalAssetPolicy(
            NATIVE_ASSET,
            AssetPolicy({
                minimumDeposit: MINIMUM_DEPOSIT,
                minimumWithdrawal: MINIMUM_WITHDRAWAL,
                canDeposit: false,
                canWithdraw: false,
                enabled: true
            })
        );
        vm.stopPrank();

        address unitOfAccount = address(periphery.unitOfAccount());

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
        oracleRouter.govSetResolvedVault(periphery.getVault(), true);
        vm.stopPrank();
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
        periphery.internalVault().approve(address(periphery), type(uint256).max);
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
