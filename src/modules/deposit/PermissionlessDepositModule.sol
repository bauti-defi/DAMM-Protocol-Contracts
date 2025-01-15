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
import {IPermissionlessDepositModule} from "@src/interfaces/IPermissionlessDepositModule.sol";
import {SafeLib} from "@src/libs/SafeLib.sol";
import {Pausable} from "@src/core/Pausable.sol";

/// @dev A module that when added to a gnosis safe, allows for anyone to deposit into the fund
/// the gnosis safe must have a valid broker account (nft) with the periphery to be able to deposit
/// on behalf of the caller.
contract PermissionlessDepositModule is Pausable, IPermissionlessDepositModule {
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

    function deposit(DepositOrder calldata order) external notPaused returns (uint256 sharesOut) {
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

    function intentDeposit(SignedDepositIntent calldata order)
        external
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

    function withdraw(WithdrawOrder calldata order)
        external
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

    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
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

    function _getAmount(ERC20 asset, uint256 amount, address user) private view returns (uint256) {
        return amount == type(uint256).max ? asset.balanceOf(user) : amount;
    }

    function increaseNonce(uint256 increment_) external {
        nonces[msg.sender] += increment_ > 1 ? increment_ : 1;
    }
}
