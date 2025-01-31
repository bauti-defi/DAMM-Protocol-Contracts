// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@src/modules/transact/Structs.sol";
import "@src/interfaces/IHookRegistry.sol";

interface ITransactionModule {
    /// @notice The fund contract address
    function fund() external returns (address);

    /// @notice Registry for transaction hooks
    function hookRegistry() external returns (IHookRegistry);

    /// @notice Executes multiple transactions through the Safe
    /// @dev Reverts all transactions if any fail
    /// @param transactions Array of transactions to execute
    function execute(Transaction[] calldata transactions) external;
}
