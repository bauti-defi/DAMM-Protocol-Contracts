// SPDX-License-Identifier: UNLICENSED
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
import {SafeLib} from "@src/libs/SafeLib.sol";
import {DepositLibs} from "./DepositLibs.sol";

event Paused();

event Unpaused();

/// @dev A module that when added to a gnosis safe, allows for anyone to deposit into the fund
/// the gnosis safe must have a valid broker account (nft) with the periphery to be able to deposit
/// on behalf of the caller.
contract PermissionlessDepositModule {
    using DepositLibs for BrokerAccountInfo;
    using SafeTransferLib for ERC20;
    using SafeLib for ISafe;

    IPeriphery public immutable periphery;
    ISafe public immutable safe;
    mapping(address user => uint256 nonce) public nonces;
    bool public paused;

    constructor(address safe_, address periphery_) {
        safe = ISafe(safe_);
        periphery = IPeriphery(periphery_);
    }

    modifier onlyAdmin() {
        if (msg.sender != address(safe)) revert Errors.OnlyAdmin();
        _;
    }

    modifier notPaused() {
        if (paused) revert Errors.Deposit_ModulePaused();
        _;
    }

    function deposit(DepositOrder calldata order) external notPaused returns (uint256 sharesOut) {
        ERC20(order.asset).safeTransferFrom(msg.sender, address(safe), order.amount);

        // call deposit through the safe
        bytes memory returnData = safe.executeAndReturnDataOrRevert(
            address(periphery),
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
            msg.sender,
            order.intent.chaindId,
            nonces[msg.sender]++,
            order.intent.nonce
        );

        ERC20(order.intent.deposit.asset).safeTransferFrom(
            msg.sender,
            address(safe),
            order.intent.deposit.amount + order.intent.relayerTip + order.intent.bribe
        );

        bytes memory returnData = safe.executeAndReturnDataOrRevert(
            address(periphery),
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
        ERC20(periphery.getVault()).safeTransferFrom(msg.sender, address(safe), order.shares);

        bytes memory returnData = safe.executeAndReturnDataOrRevert(
            address(periphery),
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
            msg.sender,
            order.intent.chaindId,
            nonces[msg.sender]++,
            order.intent.nonce
        );

        bytes memory returnData = safe.executeAndReturnDataOrRevert(
            address(periphery),
            0,
            abi.encodeWithSelector(IPeriphery.withdraw.selector, order.intent.withdraw),
            Enum.Operation.Call
        );

        assetAmountOut = abi.decode(returnData, (uint256));
    }

    function increaseNonce(uint256 increment_) external {
        nonces[msg.sender] += increment_ > 1 ? increment_ : 1;
    }

    function pause() external onlyAdmin {
        paused = true;

        emit Paused();
    }

    function unpause() external onlyAdmin {
        paused = false;

        emit Unpaused();
    }
}
