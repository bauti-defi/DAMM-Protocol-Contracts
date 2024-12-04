// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICurvePool {
    /**
     * @notice Exchange one token for another
     * @param i Index value for the token you want to sell (0-based)
     * @param j Index value for the token you want to buy (0-based)
     * @param dx Amount of `i` token to sell
     * @param min_dy Minimum amount of `j` token to receive (slippage control)
     * @return dy Amount of `j` token received
     */
    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy)
        external
        returns (uint256 dy);
}
