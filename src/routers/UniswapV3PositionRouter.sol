// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {TransferHelper} from "@src/lib/TransferHelper.sol";
import {IUniswapV3PositionRouter} from "@src/interfaces/IUniswapV3PositionRouter.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";
import {IUniswapV3SwapRouter} from "@src/interfaces/IUniswapV3SwapRouter.sol";

contract UniswapV3PositionRouter is BaseRouter, IUniswapV3PositionRouter {
    INonfungiblePositionManager public immutable uniswapV3PositionManager;

    constructor(
        address _owner,
        address _tokenWhitelistRegistry,
        address _multicallerWithSender,
        address _uniswapV3PositionManager
    ) BaseRouter(_owner, _tokenWhitelistRegistry, _multicallerWithSender) {
        uniswapV3PositionManager = INonfungiblePositionManager(_uniswapV3PositionManager);
    }

    function _ensureTokenAllowance(address token, uint256 allowanceRequired) internal {
        IERC20 tokenToApprove = IERC20(token);

        if (tokenToApprove.allowance(address(this), address(uniswapV3PositionManager)) < allowanceRequired) {
            tokenToApprove.approve(address(uniswapV3PositionManager), type(uint256).max);
        }
    }

    function _getV3PositionTokenPair(uint256 tokenId) internal view returns (address token0, address token1) {
        // get the position information
        (,, token0, token1,,,,,,,,) = uniswapV3PositionManager.positions(tokenId);
    }

    function mintPosition(INonfungiblePositionManager.MintParams calldata params) external payable override setCaller {
        if (params.recipient != caller) revert InvalidRecipient();

        // check tokens are whitelisted
        _checkTokenIsWhitelisted(caller, params.token0);
        _checkTokenIsWhitelisted(caller, params.token1);

        // ensure uniswap has enough allowance to spend our routers tokens
        _ensureTokenAllowance(params.token0, params.amount0Desired);
        _ensureTokenAllowance(params.token1, params.amount1Desired);

        // transfer funds into router
        TransferHelper.safeTransferFrom(params.token0, caller, address(this), params.amount0Desired);
        TransferHelper.safeTransferFrom(params.token1, caller, address(this), params.amount1Desired);

        // mint position
        (,, uint256 amount0, uint256 amount1) = uniswapV3PositionManager.mint(params);

        // transfer unspent funds back to sender
        if (params.amount0Desired > amount0) {
            TransferHelper.safeTransfer(params.token0, caller, params.amount0Desired - amount0);
        }
        if (params.amount1Desired > amount1) {
            TransferHelper.safeTransfer(params.token1, caller, params.amount1Desired - amount1);
        }
    }

    function collectTokensOwed(INonfungiblePositionManager.CollectParams calldata params)
        external
        payable
        override
        setCaller
    {
        if (params.recipient != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(caller, token0);
        _checkTokenIsWhitelisted(caller, token1);

        uniswapV3PositionManager.collect(params);
    }

    function increasePositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        payable
        override
        setCaller
    {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(caller, token0);
        _checkTokenIsWhitelisted(caller, token1);

        _ensureTokenAllowance(token0, params.amount0Desired);
        _ensureTokenAllowance(token1, params.amount1Desired);

        TransferHelper.safeTransferFrom(token0, caller, address(this), params.amount0Desired);
        TransferHelper.safeTransferFrom(token1, caller, address(this), params.amount1Desired);

        (, uint256 amount0, uint256 amoun1) = uniswapV3PositionManager.increaseLiquidity(params);

        if (params.amount0Desired > amount0) {
            TransferHelper.safeTransfer(token0, caller, params.amount0Desired - amount0);
        }
        if (params.amount1Desired > amoun1) {
            TransferHelper.safeTransfer(token1, caller, params.amount1Desired - amoun1);
        }
    }

    function decreasePositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        payable
        override
        setCaller
    {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(caller, token0);
        _checkTokenIsWhitelisted(caller, token1);

        uniswapV3PositionManager.decreaseLiquidity(params);
    }
}
