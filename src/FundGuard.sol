// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {BaseGuard} from "@safe-contracts/base/GuardManager.sol";
import {Enum} from "@safe-contracts/common/Enum.sol";

contract FundGuard is BaseGuard {
    address immutable fund;

    bool public paused;

    modifier onlyFund() {
        require(msg.sender == fund, "FundGuard: only fund");
        _;
    }

    modifier notPaused() {
        require(!paused, "FundGuard: paused");
        _;
    }

    constructor(address owner) {
        fund = owner;
    }

    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external override notPaused onlyFund {}

    function checkAfterExecution(bytes32 txHash, bool success)
        external
        override
        notPaused
        onlyFund
    {}
}
