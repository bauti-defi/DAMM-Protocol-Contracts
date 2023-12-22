// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {TransferHelper} from "@src/lib/TransferHelper.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";
import {IUniswapV3SwapRouter} from "@src/interfaces/IUniswapV3SwapRouter.sol";

contract UniswapV3SwapRouter is BaseRouter, IUniswapV3SwapRouter {
    ISwapRouter public immutable uniswapV3SwapRouter;

    constructor(address _owner, address _tokenWhitelistRegistry, address _uniswapV3SwapRouter)
        BaseRouter(_owner, _tokenWhitelistRegistry)
    {
        uniswapV3SwapRouter = ISwapRouter(_uniswapV3SwapRouter);
    }

    function _ensureTokenAllowance(address token, uint256 allowanceRequired) internal {
        IERC20 tokenToApprove = IERC20(token);

        if (tokenToApprove.allowance(address(this), address(uniswapV3SwapRouter)) < allowanceRequired) {
            tokenToApprove.approve(address(uniswapV3SwapRouter), type(uint256).max);
        }
    }

    function swapTokenWithV3(ISwapRouter.ExactInputSingleParams memory params) external payable override setCaller {
        if (params.recipient != caller) revert InvalidRecipient();

        // check tokens are whitelisted
        _checkTokenIsWhitelisted(caller, params.tokenIn);
        _checkTokenIsWhitelisted(caller, params.tokenOut);

        // ensure uniswap has enough allowance to spend our routers tokens
        _ensureTokenAllowance(params.tokenIn, params.amountIn);

        // store our current balance of the input token
        uint256 startBalance = IERC20(params.tokenIn).balanceOf(address(this));

        // transfer funds into router
        TransferHelper.safeTransferFrom(params.tokenIn, caller, address(this), params.amountIn);

        uniswapV3SwapRouter.exactInputSingle(params);
        uint256 diff = IERC20(params.tokenIn).balanceOf(address(this)) - startBalance;

        // return left over funds to caller
        if (diff > 0) TransferHelper.safeTransfer(params.tokenIn, caller, diff);
    }
}
