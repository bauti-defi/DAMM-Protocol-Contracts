// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@src/modules/transact/Structs.sol";

interface ITransactionModule {
    event Paused();
    event Unpaused();

    function paused() external returns (bool);
    function fund() external returns (address);

    function execute(Transaction[] calldata transactions) external;
    function setMaxGasPriorityInBasisPoints(uint256 maxMinerTipInBasisPoints) external;

    function pause() external;
    function unpause() external;
}
