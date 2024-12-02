// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {BaseHook} from "@src/hooks/BaseHook.sol";

abstract contract AaveV3Base is BaseHook {
    bytes4 constant L1_WITHDRAW_SELECTOR = IPool.withdraw.selector;
    bytes4 constant L1_SUPPLY_SELECTOR = IPool.supply.selector;
    bytes4 constant L1_BORROW_SELECTOR = IPool.borrow.selector;
    bytes4 constant L1_REPAY_SELECTOR = IPool.repay.selector;
    bytes4 constant L1_REPAY_WITH_ATOKENS_SELECTOR = IPool.repayWithATokens.selector;

    IPool public immutable aaveV3Pool;

    constructor(address _fund, address _aaveV3Pool) BaseHook(_fund) {
        aaveV3Pool = IPool(_aaveV3Pool);
    }
}
