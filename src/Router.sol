// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {IRouter} from "@src/interfaces/IRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";

contract Router is IRouter {

    address internal constant SENTINEL_TOKEN = address(0x1);

    INonfungiblePositionManager public immutable uniswapV3PositionManager;
    address public immutable owner;

    mapping(address => address) public tokenWhitelist;

    constructor(address _owner, address _uniswapV3PositionManager, address[] memory _whitelistedTokens) {
        owner = _owner;
        uniswapV3PositionManager = INonfungiblePositionManager(_uniswapV3PositionManager);

        // Register whitelisted tokens
        uint256 length = _whitelistedTokens.length;
        for (uint256 i = 0; i < length;) {
            require(_whitelistedTokens[i] != address(0), "Router: token cannot be null");
            require(tokenWhitelist[_whitelistedTokens[i]] == address(0), "Router: token already whitelisted");

            tokenWhitelist[_whitelistedTokens[i]] = tokenWhitelist[SENTINEL_TOKEN];
            tokenWhitelist[SENTINEL_TOKEN] = _whitelistedTokens[i];

            // will never overflow due to size of _whitelistedTokens
            unchecked {
                ++i;
            }
        }
    }

    function mintV3Position(INonfungiblePositionManager.MintParams calldata params) external override {
        if(params.recipient != msg.sender) revert CallerMustBeReceiptient();

        uniswapV3PositionManager.mint(params);
    }

    function burnV3Position(uint256 tokenId) external override {
        uniswapV3PositionManager.burn(tokenId);
    }

    function collectV3TokensOwed(INonfungiblePositionManager.CollectParams calldata params) external override {
        if(params.recipient != msg.sender) revert CallerMustBeReceiptient();

        uniswapV3PositionManager.collect(params);
    }

    function increaseV3PositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        override
    {
        uniswapV3PositionManager.increaseLiquidity(params);
    }


    function decreaseV3PositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        override
    {
        if(params.recipient != msg.sender) revert CallerMustBeReceiptient();

        uniswapV3PositionManager.decreaseLiquidity(params);
    }


    
}