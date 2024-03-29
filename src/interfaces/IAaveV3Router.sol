// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import {IPool} from "@src/interfaces/external/IPool.sol";

interface IAaveV3Router {
    function aaveV3Pool() external view returns (IPool);

    function deposit(address token, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external returns (uint256);
}
