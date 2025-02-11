// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {Periphery} from "@src/modules/deposit/Periphery.sol";
import {BalanceOfOracle} from "@src/oracles/BalanceOfOracle.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";
import {SignedMath} from "@openzeppelin-contracts/utils/math/SignedMath.sol";
import {MessageHashUtils} from "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
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
import {TestBaseDeposit} from "./TestBaseDeposit.sol";
import {DepositLibs} from "@src/modules/deposit/DepositLibs.sol";

abstract contract TestBasePeriphery is TestBaseDeposit, DeployPermit2 {
    using MessageHashUtils for bytes;
    using DepositLibs for DepositIntent;
    using DepositLibs for WithdrawIntent;
    using SignedMath for int256;

    bytes32 internal constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    Periphery internal periphery;
    address internal peripheryMastercopy;
    address relayer;
    address feeRecipient;
    uint256 internal feeRecipientPK;

    address permit2;

    function setUp() public virtual override(TestBaseDeposit) {
        TestBaseDeposit.setUp();

        (feeRecipient, feeRecipientPK) = makeAddrAndKey("FeeRecipient");

        relayer = makeAddr("Relayer");
        // deploy periphery using module factory
        ModuleProxyFactory factory = new ModuleProxyFactory();
        permit2 = address(deployPermit2());

        peripheryMastercopy = address(new Periphery(permit2, "1"));

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
        view
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

    modifier openAccount(address user_, uint256 ttl_, bool transferable_, bool isPublic) {
        _openAccount(user_, ttl_, transferable_, isPublic);

        _;
    }

    function _openAccount(address user_, uint256 ttl_, bool transferable_, bool isPublic)
        internal
    {
        vm.startPrank(address(fund));
        periphery.openAccount(
            CreateAccountParams({
                transferable: transferable_,
                user: user_,
                isPublic: isPublic,
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

    function peripheryHashTypedDataV4(bytes32 structHash) internal view returns (bytes32) {
        return MessageHashUtils.toTypedDataHash(periphery.domainSeparatorV4(), structHash);
    }

    function depositOrder(
        uint256 accountId,
        address minter,
        address recipient,
        address token,
        uint256 amount
    ) internal view returns (DepositOrder memory) {
        return DepositOrder({
            accountId: accountId,
            recipient: recipient,
            minter: minter,
            asset: token,
            amount: amount,
            deadline: block.timestamp + 1000,
            minSharesOut: 0,
            referralCode: 0
        });
    }

    function unsignedDepositIntent(
        uint256 accountId,
        address minter,
        address recipient,
        address token,
        uint256 amount,
        uint256 nonce,
        uint256 relayerTip,
        uint256 bribe
    ) internal view returns (DepositIntent memory) {
        return DepositIntent({
            deposit: DepositOrder({
                accountId: accountId,
                recipient: recipient,
                minter: minter,
                asset: token,
                amount: amount,
                deadline: block.timestamp + 1000,
                minSharesOut: 0,
                referralCode: 0
            }),
            chainId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: nonce
        });
    }

    function depositIntent(
        uint256 accountId,
        address minter,
        uint256 minterPk,
        address recipient,
        address token,
        uint256 amount,
        uint256 relayerTip,
        uint256 bribe,
        uint256 nonce
    ) internal view returns (SignedDepositIntent memory) {
        DepositIntent memory intent = DepositIntent({
            deposit: depositOrder(accountId, minter, recipient, token, amount),
            chainId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: nonce
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(minterPk, peripheryHashTypedDataV4(intent.hashDepositIntent()));

        return SignedDepositIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function withdrawOrder(
        uint256 accountId,
        address burner,
        address to,
        address asset,
        uint256 shares
    ) internal view returns (WithdrawOrder memory) {
        return WithdrawOrder({
            accountId: accountId,
            burner: burner,
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
        address burner,
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
                burner: burner,
                to: to,
                asset: asset,
                shares: shares,
                deadline: block.timestamp + 1000,
                minAmountOut: 0,
                referralCode: 0
            }),
            chainId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: nonce
        });
    }

    function signedWithdrawIntent(
        uint256 accountId,
        address burner,
        uint256 burnerPk,
        address to,
        address asset,
        uint256 shares,
        uint256 relayerTip,
        uint256 bribe,
        uint256 nonce
    ) internal view returns (SignedWithdrawIntent memory) {
        WithdrawIntent memory intent = WithdrawIntent({
            withdraw: withdrawOrder(accountId, burner, to, asset, shares),
            chainId: block.chainid,
            relayerTip: relayerTip,
            bribe: bribe,
            nonce: nonce
        });

        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(burnerPk, peripheryHashTypedDataV4(intent.hashWithdrawIntent()));

        return SignedWithdrawIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function signdepositIntent(DepositIntent memory intent, uint256 userPK)
        internal
        view
        returns (SignedDepositIntent memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, peripheryHashTypedDataV4(intent.hashDepositIntent()));

        return SignedDepositIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }

    function signsignedWithdrawIntent(WithdrawIntent memory intent, uint256 userPK)
        internal
        view
        returns (SignedWithdrawIntent memory)
    {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(userPK, peripheryHashTypedDataV4(intent.hashWithdrawIntent()));

        return SignedWithdrawIntent({intent: intent, signature: abi.encodePacked(r, s, v)});
    }
}
