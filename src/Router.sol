// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.21;

import {IRouter} from "@src/interfaces/IRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";

contract Router is IRouter {
    address internal constant SENTINEL_TOKEN = address(0x1);
    bytes4 internal constant ERC721_OWNER_OF_SELECTOR = bytes4(keccak256("ownerOf(uint256)"));

    INonfungiblePositionManager public immutable uniswapV3PositionManager;
    ISwapRouter public immutable uniswapV3SwapRouter;
    address public immutable owner;

    mapping(address => address) public tokenWhitelist;

    constructor(
        address _owner,
        address _uniswapV3PositionManager,
        address _uniswapV3SwapRouter,
        address[] memory _whitelistedTokens
    ) {
        owner = _owner;
        uniswapV3SwapRouter = ISwapRouter(_uniswapV3SwapRouter);
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

    function _checkTokenIsWhitelisted(address token) internal view {
        if (tokenWhitelist[token] == address(0)) revert TokenNotWhitelisted();
    }

    function _getV3PositionOwner(uint256 tokenId) internal returns (address) {
        (bool success, bytes memory data) =
            address(uniswapV3PositionManager).call(abi.encodeWithSelector(ERC721_OWNER_OF_SELECTOR, tokenId));

        require(success, "Failed to fetch V3 position owner");

        return abi.decode(data, (address));
    }

    function _getV3PositionTokenPair(uint256 tokenId) internal view returns (address token0, address token1) {
        // get the position information
        (,, token0, token1,,,,,,,,) = uniswapV3PositionManager.positions(tokenId);
    }

    function swapTokenWithV3(ISwapRouter.ExactInputSingleParams memory params) external override {
        if (params.recipient != msg.sender) revert InvalidRecipient();

        _checkTokenIsWhitelisted(params.tokenIn);
        _checkTokenIsWhitelisted(params.tokenOut);

        uniswapV3SwapRouter.exactInputSingle(params);
    }

    function mintV3Position(INonfungiblePositionManager.MintParams calldata params) external override {
        if (params.recipient != msg.sender) revert InvalidRecipient();

        _checkTokenIsWhitelisted(params.token0);
        _checkTokenIsWhitelisted(params.token1);

        uniswapV3PositionManager.mint(params);
    }

    function collectV3TokensOwed(INonfungiblePositionManager.CollectParams calldata params) external override {
        if (params.recipient != msg.sender) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(token0);
        _checkTokenIsWhitelisted(token1);

        uniswapV3PositionManager.collect(params);
    }

    function increaseV3PositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        override
    {
        address positionOwner = _getV3PositionOwner(params.tokenId);

        if (positionOwner != msg.sender) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(token0);
        _checkTokenIsWhitelisted(token1);

        uniswapV3PositionManager.increaseLiquidity(params);
    }

    function decreaseV3PositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        override
    {
        address positionOwner = _getV3PositionOwner(params.tokenId);

        if (positionOwner != msg.sender) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(token0);
        _checkTokenIsWhitelisted(token1);

        uniswapV3PositionManager.decreaseLiquidity(params);
    }
}
