// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Test} from "@forge-std/Test.sol";

import {MulticallerEtcher} from "@vec-multicaller/MulticallerEtcher.sol";
import {MulticallerWithSender} from "@vec-multicaller/MulticallerWithSender.sol";

abstract contract BaseMulticallerWithSender is Test {
    MulticallerWithSender public multicallerWithSender;

    function setUp() public virtual {
        multicallerWithSender = MulticallerEtcher.multicallerWithSender();

        vm.label(address(multicallerWithSender), "MulticallerWithSender");
    }
}
