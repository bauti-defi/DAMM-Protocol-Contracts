// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IPool} from "@src/interfaces/external/IPool.sol";
import {IAaveV3Router} from "@src/interfaces/IAaveV3Router.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";

contract AaveV3Router is BaseRouter, IAaveV3Router {
    IPool public immutable aaveV3Pool;

    constructor(
        address _owner,
        address _WETH9,
        address _tokenWhitelistRegistry,
        address _multicallerWithSender,
        address _aaveV3Pool
    ) BaseRouter(_owner, _WETH9, _tokenWhitelistRegistry, _multicallerWithSender) {
        aaveV3Pool = IPool(_aaveV3Pool);
    }

    function _ensureTokenAllowance(address token, uint256 allowanceRequired) internal {
        IERC20 tokenToApprove = IERC20(token);

        if (tokenToApprove.allowance(address(this), address(aaveV3Pool)) < allowanceRequired) {
            tokenToApprove.approve(address(aaveV3Pool), type(uint256).max);
        }
    }

    function supplyAAVE(address token, uint256 amount) external override setCaller {
        _checkTokenIsWhitelisted(caller, token);

        aaveV3Pool.supply(token, amount, caller, 0);
    }

    function withdrawAAVE(address asset, uint256 amount) external override setCaller {
        _checkTokenIsWhitelisted(caller, asset);

        aaveV3Pool.withdraw(asset, amount, caller);
    }
}
