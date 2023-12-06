// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IRouter} from "@src/interfaces/IRouter.sol";
import {INonfungiblePositionManager} from "@src/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@src/interfaces/ISwapRouter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";
import {TransferHelper} from "@src/lib/TransferHelper.sol";
import {ReentrancyGuard} from "@src/lib/ReentrancyGuard.sol";
import {IMulticall} from "@src/interfaces/IMulticall.sol";

contract Router is IRouter, IMulticall, ReentrancyGuard {

    modifier setCaller {
        caller = msg.sender;
        _;
        caller = address(0);
    }

    address internal constant SENTINEL_TOKEN = address(0x1);
    
    address internal caller;

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

        tokenWhitelist[SENTINEL_TOKEN] = SENTINEL_TOKEN;

        // Register whitelisted tokens
        uint256 length = _whitelistedTokens.length;
        for (uint256 i = 0; i < length;) {
            require(_whitelistedTokens[i] != address(0), "Router: token cannot be null");
            require(tokenWhitelist[_whitelistedTokens[i]] == address(0), "Router: token already whitelisted");

            tokenWhitelist[_whitelistedTokens[i]] = tokenWhitelist[SENTINEL_TOKEN];
            tokenWhitelist[SENTINEL_TOKEN] = _whitelistedTokens[i];

            // approve uniswap contracts to spend whitelisted tokens indefinitely
            require(
                IERC20(_whitelistedTokens[i]).approve(_uniswapV3PositionManager, type(uint256).max),
                "Router: token approval to position manager failed"
            );
            require(
                IERC20(_whitelistedTokens[i]).approve(_uniswapV3SwapRouter, type(uint256).max),
                "Router: token approval to swap router failed"
            );

            // will never overflow due to size of _whitelistedTokens
            unchecked {
                ++i;
            }
        }
    }

    function multicall(bytes[] calldata data) external payable override nonReentrant returns (bytes[] memory results)  {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }

    function isTokenWhitelisted(address token) public view returns (bool) {
        return tokenWhitelist[token] != address(0) && token != SENTINEL_TOKEN;
    }

    function _checkTokenIsWhitelisted(address token) internal view {
        if (!isTokenWhitelisted(token)) revert TokenNotWhitelisted();
    }

    function _getV3PositionTokenPair(uint256 tokenId) internal view returns (address token0, address token1) {
        // get the position information
        (,, token0, token1,,,,,,,,) = uniswapV3PositionManager.positions(tokenId);
    }

    function swapTokenWithV3(ISwapRouter.ExactInputSingleParams memory params) external override setCaller {
        if (params.recipient != caller) revert InvalidRecipient();

        _checkTokenIsWhitelisted(params.tokenIn);
        _checkTokenIsWhitelisted(params.tokenOut);

        // store our current balance of the input token
        uint256 startBalance = IERC20(params.tokenIn).balanceOf(address(this));

        // transfer funds into router
        TransferHelper.safeTransferFrom(params.tokenIn, caller, address(this), params.amountIn);

        uniswapV3SwapRouter.exactInputSingle(params);
        uint256 diff = IERC20(params.tokenIn).balanceOf(address(this)) - startBalance;

        // return left over funds to caller
        if (diff > 0) TransferHelper.safeTransfer(params.tokenIn, caller, diff);
    }

    function mintV3Position(INonfungiblePositionManager.MintParams calldata params) external override setCaller {
        if (params.recipient != caller) revert InvalidRecipient();

        // check tokens are whitelisted
        _checkTokenIsWhitelisted(params.token0);
        _checkTokenIsWhitelisted(params.token1);

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

    function collectV3TokensOwed(INonfungiblePositionManager.CollectParams calldata params) external override setCaller {
        if (params.recipient != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(token0);
        _checkTokenIsWhitelisted(token1);

        uniswapV3PositionManager.collect(params);
    }

    function increaseV3PositionLiquidity(INonfungiblePositionManager.IncreaseLiquidityParams calldata params)
        external
        override
        setCaller
    {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(token0);
        _checkTokenIsWhitelisted(token1);

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

    function decreaseV3PositionLiquidity(INonfungiblePositionManager.DecreaseLiquidityParams calldata params)
        external
        override
        setCaller
    {
        address positionOwner = IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId);

        if (positionOwner != caller) revert InvalidRecipient();

        (address token0, address token1) = _getV3PositionTokenPair(params.tokenId);

        _checkTokenIsWhitelisted(token0);
        _checkTokenIsWhitelisted(token1);

        uniswapV3PositionManager.decreaseLiquidity(params);
    }

    fallback() external payable {
        revert("Router: invalid fallback");
    }

    receive () external payable {
        revert("Router: invalid receive");
    }

}
