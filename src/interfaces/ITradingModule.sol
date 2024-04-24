// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface ITradingModule {
    error UndefinedHooks();
    error InvalidTransactionLength();
    error GasLimitExceeded();

    event Paused();
    event Unpaused();

    function paused() external returns (bool);
    function fund() external returns (address);

    function execute(bytes memory transaction) external;
    function setMaxMinerTipInBasisPoints(uint256 maxMinerTipInBasisPoints) external;

    function pause() external;
    function unpause() external;
}
