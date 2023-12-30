// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IPool} from "@src/interfaces/external/IPool.sol";

interface IAaveV3Router {
    function aaveV3Pool() external view returns (IPool);

    function supplyAAVE(address token, uint256 amount) external;

    function withdrawAAVE(address asset, uint256 amount) external;
}
