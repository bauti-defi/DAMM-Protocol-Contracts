// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import "@src/oracles/TrustedRateOracle.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {FixedRateOracle} from "@euler-price-oracle/adapter/fixed/FixedRateOracle.sol";

contract TestTrustedRateOracle is Test {
    FixedRateOracle public fixedRateOracle;
    TrustedRateOracle public trustedRateOracle;
    MockERC20 internal token0;
    MockERC20 internal token1;

    function setUp() public {
        token0 = new MockERC20(8);
        vm.label(address(token0), "token0");
        token1 = new MockERC20(8);
        vm.label(address(token1), "token1");
    }

    /// @notice The trusted oracle is just a permissioned version of the fixed oracle.
    /// @dev we do differencial testing to ensure that the trusted oracle is working as expected.
    function test_oracle_valuation(uint256 _amount, uint256 _rate, uint256 _validUntil) public {
        vm.assume(_rate > 0);
        vm.assume(_validUntil >= block.timestamp);
        uint256 rate = bound(_rate, 1, type(uint128).max);
        uint256 validUntil = _validUntil;
        uint256 amount = bound(_amount, 1, type(uint128).max);

        trustedRateOracle = new TrustedRateOracle(address(this), address(token0), address(token1));
        fixedRateOracle = new FixedRateOracle(address(token0), address(token1), rate);

        trustedRateOracle.updateRate(rate, validUntil);

        assertEq(trustedRateOracle.rate(), rate);
        assertEq(trustedRateOracle.lastUpdate(), block.timestamp);
        assertEq(trustedRateOracle.priceValidUntil(), validUntil);

        uint256 t_amountOut = trustedRateOracle.getQuote(amount, address(token1), address(token0));
        uint256 f_amountOut = fixedRateOracle.getQuote(amount, address(token1), address(token0));
        assertEq(t_amountOut, f_amountOut);
    }

    function test_only_owner_can_update_rate(address attacker) public {
        vm.assume(attacker != address(this));
        trustedRateOracle = new TrustedRateOracle(address(this), address(token0), address(token1));
        vm.prank(attacker);
        vm.expectRevert();
        trustedRateOracle.updateRate(1, block.timestamp + 1);
    }

    function test_only_real_rate_can_be_set(uint256 rate) public {
        vm.assume(rate > 0);
        trustedRateOracle = new TrustedRateOracle(address(this), address(token0), address(token1));

        assertEq(trustedRateOracle.rate(), 0);

        vm.expectRevert();
        trustedRateOracle.updateRate(0, block.timestamp + 1);

        trustedRateOracle.updateRate(rate, block.timestamp + 1);
        assertEq(trustedRateOracle.rate(), rate);
    }

    function test_rate_must_be_set_in_the_future(
        uint256 blockTimestamp,
        uint256 badValidUntil,
        uint256 goodValidUntil
    ) public {
        vm.assume(blockTimestamp > 0);
        vm.assume(badValidUntil < blockTimestamp);
        vm.assume(goodValidUntil >= blockTimestamp);

        vm.warp(blockTimestamp);
        trustedRateOracle = new TrustedRateOracle(address(this), address(token0), address(token1));
        vm.expectRevert();
        trustedRateOracle.updateRate(1, badValidUntil);

        trustedRateOracle.updateRate(1, goodValidUntil);
    }
}
