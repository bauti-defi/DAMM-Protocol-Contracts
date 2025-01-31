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
import {IDepositModule} from "@src/interfaces/IDepositModule.sol";
import "@openzeppelin-contracts/utils/Pausable.sol";

/// @title Deposit Module Base Implementation
/// @notice A Gnosis Safe module that provides deposit and withdrawal functionality
/// @dev A gnosis safe module that provides deposit and withdraw functionality
///      Has a 1-1 relationship with a safe and periphery
///      the safe must have a valid broker account (nft) from the periphery
abstract contract DepositModule is IDepositModule {
    using DepositLibs for BrokerAccountInfo;
    using SafeLib for ISafe;
    using SafeTransferLib for ERC20;

    /// @notice The periphery contract address
    address public immutable periphery;

    /// @notice The Gnosis Safe this module is attached to
    address public immutable safe;

    /// @notice The fund contract address
    address public immutable fund;

    /// @notice Mapping of user nonces for replay protection
    mapping(address user => uint256 nonce) public nonces;

    /// @notice Creates a new deposit module
    /// @param fund_ The fund contract address
    /// @param safe_ The Gnosis Safe address
    /// @param periphery_ The periphery contract address
    constructor(address fund_, address safe_, address periphery_) {
        fund = fund_;
        safe = safe_;
        periphery = periphery_;
    }

    /// @notice Internal deposit implementation
    /// @dev Transfers assets from sender and executes deposit through safe
    /// @param order The deposit order parameters
    /// @return sharesOut Amount of shares minted
    function _deposit(DepositOrder calldata order) internal returns (uint256 sharesOut) {
        ERC20 asset = ERC20(order.asset);
        uint256 amount = _getAmount(asset, order.amount, msg.sender);

        /// @notice send the assets to the safe
        /// since safe is the holder of the brokerage nft
        /// it will call periphery to deposit on behalf of the sender
        asset.safeTransferFrom(msg.sender, safe, amount);

        bytes memory returnData = ISafe(safe).executeAndReturnDataOrRevert(
            periphery,
            0,
            abi.encodeWithSelector(IPeriphery.deposit.selector, order),
            Enum.Operation.Call
        );

        sharesOut = abi.decode(returnData, (uint256));
    }

    /// @notice Internal implementation for intent-based deposits
    /// @dev Handles relayer tips, bribes, and executes deposit through safe
    /// @param order The signed deposit intent
    /// @return sharesOut Amount of shares minted
    function _intentDeposit(SignedDepositIntent calldata order)
        internal
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
                fund,
                order.intent.bribe
            );
        }

        uint256 amount =
            _getAmount(asset, order.intent.deposit.amount, order.intent.deposit.recipient);

        /// transfer the remaining amount to the safe to be deposited
        /// @dev transfer assets after paying the bribe and relayer tip incase amount = max uint256
        asset.safeTransferFrom(order.intent.deposit.recipient, safe, amount);

        bytes memory returnData = ISafe(safe).executeAndReturnDataOrRevert(
            periphery,
            0,
            abi.encodeWithSelector(IPeriphery.deposit.selector, order.intent.deposit),
            Enum.Operation.Call
        );

        sharesOut = abi.decode(returnData, (uint256));
    }

    /// @notice Internal withdrawal implementation
    /// @dev Transfers shares from sender and executes withdrawal through safe
    /// @param order The withdrawal order parameters
    /// @return assetAmountOut Amount of assets withdrawn
    function _withdraw(WithdrawOrder calldata order) internal returns (uint256 assetAmountOut) {
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

    /// @notice Internal implementation for intent-based withdrawals
    /// @dev Handles relayer tips, bribes, and executes withdrawal through safe
    /// @param order The signed withdrawal intent
    /// @return assetAmountOut Amount of assets withdrawn
    function _intentWithdraw(SignedWithdrawIntent calldata order)
        internal
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
            asset.safeTransferFrom(order.intent.withdraw.to, fund, order.intent.bribe);
        }
    }

    /// @notice Helper to get actual transfer amount
    /// @dev Returns user's full balance if amount is max uint256
    /// @param asset The token to check
    /// @param amount The requested amount
    /// @param user The user to check balance for
    /// @return The actual amount to transfer
    function _getAmount(ERC20 asset, uint256 amount, address user)
        internal
        view
        returns (uint256)
    {
        return amount == type(uint256).max ? asset.balanceOf(user) : amount;
    }

    /// @notice Increases a user's nonce
    /// @param increment_ Amount to increase nonce by (minimum 1)
    function increaseNonce(uint256 increment_) external {
        nonces[msg.sender] += increment_ > 1 ? increment_ : 1;
    }
}
