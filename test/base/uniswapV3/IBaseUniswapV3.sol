// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.7.0;

interface IBaseUniswapV3 {
    function factory() external view returns (address);
    function weth9() external view returns (address);
    function tokenDescriptor() external view returns (address);
    function positionManager() external view returns (address);
    function router() external view returns (address);
    function deployPool(address token0, address token1, uint24 poolFee)
        external
        returns (address pool);
    function initializePool(address pool, int24 startTick) external;
}
