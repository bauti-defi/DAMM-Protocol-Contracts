// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {TransferHelper} from "@src/lib/TransferHelper.sol";
import {IUniswapV3PositionRouter} from "@src/interfaces/IUniswapV3PositionRouter.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";
import "@src/lib/ProtocolStateAccesor.sol";
import {IProtocolState} from "@src/interfaces/IProtocolState.sol";

contract UniswapV3PositionRouter is BaseRouter, IUniswapV3PositionRouter {
    INonfungiblePositionManager public immutable uniswapV3PositionManager;

    constructor(
        address _protocolState,
        address _WETH9,
        address _tokenWhitelistRegistry,
        address _multicallerWithSender,
        address _uniswapV3PositionManager
    ) BaseRouter(_protocolState, _WETH9, _tokenWhitelistRegistry, _multicallerWithSender) {
        uniswapV3PositionManager = INonfungiblePositionManager(_uniswapV3PositionManager);
    }

    function _ensureTokenAllowance(address token, uint256 allowanceRequired) internal {
        IERC20 tokenToApprove = IERC20(token);

        if (tokenToApprove.allowance(address(this), address(uniswapV3PositionManager)) < allowanceRequired) {
            require(
                tokenToApprove.approve(address(uniswapV3PositionManager), type(uint256).max), "Router: approve failed"
            );
        }
    }

    function _getV3PositionTokenPair(uint256 tokenId) internal view returns (address token0, address token1) {
        // get the position information
        (,, token0, token1,,,,,,,,) = uniswapV3PositionManager.positions(tokenId);
    }

    function mintPosition(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        override
        notPaused
        setCaller
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (params.recipient != caller) revert InvalidRecipient();

        // check tokens are whitelisted
        _checkTokensAreWhitelisted(caller, abi.encodePacked(params.token0, params.token1));

        // ensure uniswap has enough allowance to spend our routers tokens
        _ensureTokenAllowance(params.token0, params.amount0Desired);
        _ensureTokenAllowance(params.token1, params.amount1Desired);

        // transfer funds into router
        transfer(params.token0, caller, address(this), params.amount0Desired);
        transfer(params.token1, caller, address(this), params.amount1Desired);

        // mint position
        (tokenId, liquidity, amount0, amount1) = uniswapV3PositionManager.mint(params);

        // transfer unspent funds back to sender
        if (params.amount0Desired > amount0) {
            transfer(params.token0, address(this), caller, params.amount0Desired - amount0);
        }
        if (params.amount1Desired > amount1) {
            transfer(params.token1, address(this), caller, params.amount1Desired - amount1);
        }
    }

    function collectTokensOwed(INonfungiblePositionManager.CollectParams calldata params)
        external
        payable
        override
        notPaused
        setCaller
        returns (uint256 amount0, uint256 amount1)
    {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller || params.recipient != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokensAreWhitelisted(caller, abi.encodePacked(token0, token1));

        (amount0, amount1) = uniswapV3PositionManager.collect(params);
    }

    function increasePositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        payable
        override
        notPaused
        setCaller
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokensAreWhitelisted(caller, abi.encodePacked(token0, token1));

        _ensureTokenAllowance(token0, params.amount0Desired);
        _ensureTokenAllowance(token1, params.amount1Desired);

        transfer(token0, caller, address(this), params.amount0Desired);
        transfer(token1, caller, address(this), params.amount1Desired);

        (liquidity, amount0, amount1) = uniswapV3PositionManager.increaseLiquidity(params);

        if (params.amount0Desired > amount0) {
            transfer(token0, address(this), caller, params.amount0Desired - amount0);
        }
        if (params.amount1Desired > amount1) {
            transfer(token1, address(this), caller, params.amount1Desired - amount1);
        }
    }

    function decreasePositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        payable
        override
        notPaused
        setCaller
        returns (uint256 amount0, uint256 amount1)
    {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokensAreWhitelisted(caller, abi.encodePacked(token0, token1));

        (amount0, amount1) = uniswapV3PositionManager.decreaseLiquidity(params);
    }
}
