// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.6;
pragma abicoder v2;

import {Test, console2} from "@forge-std/Test.sol";
import {UniswapV3Pool} from "@uniswap-v3-core/UniswapV3Pool.sol";
import {PoolAddress} from "@uniswap-v3-periphery/libraries/PoolAddress.sol";

contract TestPoolAddress is Test {
    uint24 constant FEE = 500;
    address token0;
    address token1;
    address factory;

    function setUp() public {
        token0 = makeAddr("token0");
        token1 = makeAddr("token1");
        factory = makeAddr("factory");
    }

    /// @notice This test is to verify that the PoolAddress library downloaded as a dep is working as expected.
    /// If the test fails, you should expect the rest of the uniswap test suite to not work.
    /// @dev To fix this, you should update the INIT_CODE_HASH in the PoolAddress.sol (lib/v3-periphery/contracts/libraries/PoolAddress.sol)
    /// library to match the one printed at the end of this test.
    function test_pool_address_calc() public {
        address expectedPool = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        factory,
                        keccak256(abi.encode(token0, token1, FEE)),
                        keccak256(type(UniswapV3Pool).creationCode)
                    )
                )
            )
        );

        address poolFromLib = PoolAddress.computeAddress(factory, PoolAddress.getPoolKey(token0, token1, FEE));
        assertEq(expectedPool, poolFromLib);

        if (expectedPool != poolFromLib) console2.logBytes32(keccak256(type(UniswapV3Pool).creationCode));
    }
}
