// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {
    DepositOrder,
    SignedDepositIntent,
    WithdrawOrder,
    SignedWithdrawIntent,
    BrokerAccountInfo
} from "./Structs.sol";
import {IPeriphery} from "@src/interfaces/IPeriphery.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@solmate/tokens/ERC20.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";
import {DepositLibs} from "./DepositLibs.sol";
import {SafeLib} from "@src/libs/SafeLib.sol";
import {Pausable} from "@src/core/Pausable.sol";
import {IDepositModule} from "@src/interfaces/IDepositModule.sol";

/// @dev A gnosis safe module that provides deposit and withdraw functionality
/// Has a 1-1 relationship with a safe and periphery
/// the safe must have a valid broker account (nft) from the periphery
abstract contract DepositModule is Pausable, IDepositModule {
    using DepositLibs for BrokerAccountInfo;
    using SafeLib for ISafe;
    using SafeTransferLib for ERC20;

    address public immutable periphery;
    address public immutable safe;
    mapping(address user => uint256 nonce) public nonces;

    constructor(address fund_, address safe_, address periphery_) Pausable(fund_) {
        safe = safe_;
        periphery = periphery_;
    }

    modifier onlyAdmin() {
        if (msg.sender != safe) revert Errors.OnlyAdmin();
        _;
    }

    function _deposit(DepositOrder calldata order) internal notPaused returns (uint256 sharesOut) {
        ERC20 asset = ERC20(order.asset);
        uint256 amount = _getAmount(asset, order.amount, msg.sender);
        asset.safeTransferFrom(msg.sender, safe, amount);

        // call deposit through the safe
        bytes memory returnData = ISafe(safe).executeAndReturnDataOrRevert(
            periphery,
            0,
            abi.encodeWithSelector(IPeriphery.deposit.selector, order),
            Enum.Operation.Call
        );

        sharesOut = abi.decode(returnData, (uint256));
    }

    function _intentDeposit(SignedDepositIntent calldata order)
        internal
        notPaused
        returns (uint256 sharesOut)
    {
        DepositLibs.validateIntent(
            abi.encode(order.intent),
            order.signature,
            order.intent.deposit.recipient,
            order.intent.chaindId,
            nonces[order.intent.deposit.recipient]++,
            order.intent.nonce
        );

        ERC20 asset = ERC20(order.intent.deposit.asset);

        /// if there is a relayer tip, we need to transfer it to the relayer
        if (order.intent.relayerTip > 0) {
            asset.safeTransferFrom(
                order.intent.deposit.recipient, msg.sender, order.intent.relayerTip
            );
        }

        /// if there is a bribe, we need to transfer it to the fund
        if (order.intent.bribe > 0) {
            asset.safeTransferFrom(
                order.intent.deposit.recipient,
                address(IPeriphery(periphery).fund()),
                order.intent.bribe
            );
        }

        uint256 amount =
            _getAmount(asset, order.intent.deposit.amount, order.intent.deposit.recipient);

        /// transfer the remaining amount to the safe to be deposited
        asset.safeTransferFrom(order.intent.deposit.recipient, safe, amount);

        bytes memory returnData = ISafe(safe).executeAndReturnDataOrRevert(
            periphery,
            0,
            abi.encodeWithSelector(IPeriphery.deposit.selector, order.intent.deposit),
            Enum.Operation.Call
        );

        sharesOut = abi.decode(returnData, (uint256));
    }

    function _withdraw(WithdrawOrder calldata order)
        internal
        notPaused
        returns (uint256 assetAmountOut)
    {
        ERC20 asset = ERC20(IPeriphery(periphery).getVault());
        uint256 amount = _getAmount(asset, order.shares, msg.sender);
        asset.safeTransferFrom(msg.sender, safe, amount);

        bytes memory returnData = ISafe(safe).executeAndReturnDataOrRevert(
            periphery,
            0,
            abi.encodeWithSelector(IPeriphery.withdraw.selector, order),
            Enum.Operation.Call
        );

        assetAmountOut = abi.decode(returnData, (uint256));
    }

    function _intentWithdraw(SignedWithdrawIntent calldata order)
        internal
        notPaused
        returns (uint256 assetAmountOut)
    {
        DepositLibs.validateIntent(
            abi.encode(order.intent),
            order.signature,
            order.intent.withdraw.to,
            order.intent.chaindId,
            nonces[order.intent.withdraw.to]++,
            order.intent.nonce
        );

        ERC20 asset = ERC20(IPeriphery(periphery).getVault());
        uint256 amount = _getAmount(asset, order.intent.withdraw.shares, order.intent.withdraw.to);
        asset.safeTransferFrom(order.intent.withdraw.to, safe, amount);

        bytes memory returnData = ISafe(safe).executeAndReturnDataOrRevert(
            periphery,
            0,
            abi.encodeWithSelector(IPeriphery.withdraw.selector, order.intent.withdraw),
            Enum.Operation.Call
        );

        assetAmountOut = abi.decode(returnData, (uint256));

        asset = ERC20(order.intent.withdraw.asset);

        /// if there is a relayer tip, we need to transfer it to the relayer
        if (order.intent.relayerTip > 0) {
            asset.safeTransferFrom(order.intent.withdraw.to, msg.sender, order.intent.relayerTip);
        }

        /// if there is a bribe, we need to transfer it to the fund
        if (order.intent.bribe > 0) {
            asset.safeTransferFrom(
                order.intent.withdraw.to, address(IPeriphery(periphery).fund()), order.intent.bribe
            );
        }
    }

    function _getAmount(ERC20 asset, uint256 amount, address user)
        internal
        view
        returns (uint256)
    {
        return amount == type(uint256).max ? asset.balanceOf(user) : amount;
    }

    function increaseNonce(uint256 increment_) external {
        nonces[msg.sender] += increment_ > 1 ? increment_ : 1;
    }
}
