// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "@src/modules/transact/Structs.sol";
import "@src/interfaces/IHookRegistry.sol";

interface ITransactionModule {
    function fund() external returns (address);
    function hookRegistry() external returns (IHookRegistry);

    function execute(Transaction[] calldata transactions) external;
}
