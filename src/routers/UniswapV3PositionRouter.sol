// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IUniswapV3PositionRouter} from "@src/interfaces/IUniswapV3PositionRouter.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import "@src/lib/RouterPayments.sol";

contract UniswapV3PositionRouter is BaseRouter, RouterPayments, IUniswapV3PositionRouter {
    INonfungiblePositionManager public immutable uniswapV3PositionManager;

    constructor(
        IProtocolAddressRegistry _addressRegsitry,
        IWETH9 _WETH9,
        INonfungiblePositionManager _uniswapV3PositionManager
    ) BaseRouter(_addressRegsitry) RouterPayments(_WETH9) {
        uniswapV3PositionManager = _uniswapV3PositionManager;
    }

    function _getV3PositionTokenPair(uint256 tokenId)
        internal
        view
        returns (address token0, address token1)
    {
        // get the position information
        (,, token0, token1,,,,,,,,) = uniswapV3PositionManager.positions(tokenId);
    }

    function mintPosition(INonfungiblePositionManager.MintParams calldata params)
        external
        override
        notPaused
        setCaller
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        if (params.recipient != caller) revert InvalidRecipient();

        // check tokens are whitelisted
        _checkTokensAreWhitelisted(caller, abi.encodePacked(params.token0, params.token1));

        // ensure uniswap has enough allowance to spend our routers tokens
        safelyEnsureTokenAllowance(
            params.token0, address(uniswapV3PositionManager), params.amount0Desired
        );
        safelyEnsureTokenAllowance(
            params.token1, address(uniswapV3PositionManager), params.amount1Desired
        );

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

    function increasePositionLiquidity(
        INonfungiblePositionManager.IncreaseLiquidityParams calldata params
    )
        external
        override
        notPaused
        setCaller
        returns (uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokensAreWhitelisted(caller, abi.encodePacked(token0, token1));

        safelyEnsureTokenAllowance(token0, address(uniswapV3PositionManager), params.amount0Desired);
        safelyEnsureTokenAllowance(token1, address(uniswapV3PositionManager), params.amount1Desired);

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

    function decreasePositionLiquidity(
        INonfungiblePositionManager.DecreaseLiquidityParams calldata params
    ) external override notPaused setCaller returns (uint256 amount0, uint256 amount1) {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokensAreWhitelisted(caller, abi.encodePacked(token0, token1));

        (amount0, amount1) = uniswapV3PositionManager.decreaseLiquidity(params);
    }
}
