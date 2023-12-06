// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";
import {IPool} from "@src/interfaces/IPool.sol";

abstract contract BaseAaveV3 is Test {
    address constant AAVE_V3_POOL = 0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    IPool public constant aaveV3Pool = IPool(AAVE_V3_POOL);

    function setUp() public virtual {
        vm.label(AAVE_V3_POOL, "AAVE_V3_POOL");
    }
}
