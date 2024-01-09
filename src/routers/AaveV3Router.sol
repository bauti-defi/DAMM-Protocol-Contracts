// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {IAaveV3Router} from "@src/interfaces/IAaveV3Router.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {IPool} from "@src/interfaces/external/IPool.sol";

contract AaveV3Router is BaseRouter, IAaveV3Router {
    IPool public immutable aaveV3Pool;

    constructor(IProtocolAddressRegistry _addressRegsitry, IPool _aaveV3Pool)
        BaseRouter(_addressRegsitry)
    {
        aaveV3Pool = _aaveV3Pool;
    }

    function deposit(address token, uint256 amount) external override notPaused setCaller {
        _checkTokenIsWhitelisted(caller, token);
        // safelyEnsureTokenAllowance(token, address(aaveV3Pool), type(uint256).max);

        aaveV3Pool.supply(token, amount, caller, 0);
    }

    function withdraw(address token, uint256 amount)
        external
        override
        notPaused
        setCaller
        returns (uint256)
    {
        _checkTokenIsWhitelisted(caller, token);
        // safelyEnsureTokenAllowance(token, address(aaveV3Pool), type(uint256).max);

        return aaveV3Pool.withdraw(token, amount, caller);
    }
}
