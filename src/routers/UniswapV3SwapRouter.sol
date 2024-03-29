// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {ISwapRouter} from "@src/interfaces/external/ISwapRouter.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";
import {IUniswapV3SwapRouter} from "@src/interfaces/IUniswapV3SwapRouter.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import "@src/lib/RouterPayments.sol";

contract UniswapV3SwapRouter is BaseRouter, RouterPayments, IUniswapV3SwapRouter {
    ISwapRouter public immutable uniswapV3SwapRouter;

    constructor(
        IProtocolAddressRegistry _addressRegsitry,
        IWETH9 _WETH9,
        ISwapRouter _uniswapV3SwapRouter
    ) BaseRouter(_addressRegsitry) RouterPayments(_WETH9) {
        uniswapV3SwapRouter = _uniswapV3SwapRouter;
    }

    function swapToken(ISwapRouter.ExactInputSingleParams memory params)
        external
        override
        notPaused
        setCaller
        returns (uint256 amountOut)
    {
        if (params.recipient != caller) revert InvalidRecipient();

        // check tokens are whitelisted
        _checkTokensAreWhitelisted(caller, abi.encodePacked(params.tokenIn, params.tokenOut));

        // ensure uniswap has enough allowance to spend our routers tokens
        safelyEnsureTokenAllowance(params.tokenIn, address(uniswapV3SwapRouter), params.amountIn);

        // store our current balance of the input token
        uint256 startBalance = IERC20(params.tokenIn).balanceOf(address(this));

        // transfer funds into router
        transfer(params.tokenIn, caller, address(this), params.amountIn);

        amountOut = uniswapV3SwapRouter.exactInputSingle(params);
        uint256 diff = IERC20(params.tokenIn).balanceOf(address(this)) - startBalance;

        // return left over funds to caller
        if (diff > 0) transfer(params.tokenIn, address(this), caller, diff);
    }
}
