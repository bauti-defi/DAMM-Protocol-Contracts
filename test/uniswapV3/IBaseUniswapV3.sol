// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.0;

interface IBaseUniswapV3 {
    function localUniV3Factory() external view returns (address);
    function weth9() external view returns (address);
    function localUniV3TokenDescriptor() external view returns (address);
    function localUniV3PM() external view returns (address);
    function localUniV3Router() external view returns (address);
}
