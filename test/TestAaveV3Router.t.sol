// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {Test} from "@forge-std/Test.sol";

import {TokenMinter} from "@test/base/TokenMinter.sol";
import {BaseAaveV3} from "@test/base/BaseAaveV3.sol";

contract TestAaveV3Router is Test, TokenMinter, BaseAaveV3 {
    function setUp() public override(TokenMinter, BaseAaveV3) {
        super.setUp();
    }

    function test_supply() public {}
}
