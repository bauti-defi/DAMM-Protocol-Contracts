// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {FundFactory} from "@src/core/FundFactory.sol";
import {IFund} from "@src/interfaces/IFund.sol";

abstract contract TestBaseFund is TestBaseGnosis {
    IFund internal fund;
    FundFactory internal fundFactory;

    function setUp() public virtual override(TestBaseGnosis) {
        TestBaseGnosis.setUp();

        fundFactory = new FundFactory();
        vm.label(address(fundFactory), "FundFactory");
    }
}
