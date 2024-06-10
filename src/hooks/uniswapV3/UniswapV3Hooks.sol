// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";
import {IUniswapRouter} from "@src/interfaces/external/IUniswapRouter.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";

error UniswapV3Hooks_OnlyFund();
error UniswapV3Hooks_OnlyWhitelistedTokens();
error UniswapV3Hooks_InvalidPosition();
error UniswapV3Hooks_InvalidTargetAddress();
error UniswapV3Hooks_InvalidTargetSelector();
error UniswapV3Hooks_InvalidAsset();

event UniswapV3Hooks_AssetEnabled(address asset);

event UniswapV3Hooks_AssetDisabled(address asset);

contract UniswapV3Hooks is IBeforeTransaction, IAfterTransaction {
    address public immutable fund;
    INonfungiblePositionManager public immutable uniswapV3PositionManager;
    IUniswapRouter public immutable uniswapV3Router;

    mapping(address asset => bool whitelisted) public assetWhitelist;

    constructor(address _fund, address _uniswapV3PositionManager, address _uniswapV3Router) {
        fund = _fund;
        uniswapV3PositionManager = INonfungiblePositionManager(_uniswapV3PositionManager);
        uniswapV3Router = IUniswapRouter(_uniswapV3Router);
    }

    function _checkPosition(uint256 tokenId) internal view {
        if (IERC721(address(uniswapV3PositionManager)).ownerOf(tokenId) != fund) {
            revert UniswapV3Hooks_InvalidPosition();
        }

        // get the position information
        (,, address token0, address token1,,,,,,,,) = uniswapV3PositionManager.positions(tokenId);

        if (!assetWhitelist[token0] || !assetWhitelist[token1]) {
            revert UniswapV3Hooks_OnlyWhitelistedTokens();
        }
    }

    modifier onlyFund() {
        if (msg.sender != fund) revert UniswapV3Hooks_OnlyFund();
        _;
    }

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8,
        uint256,
        bytes calldata data
    ) external view override onlyFund {
        if (target == address(uniswapV3PositionManager)) {
            if (selector == INonfungiblePositionManager.mint.selector) {
                address token0;
                address token1;
                address recipient;

                assembly {
                    token0 := calldataload(data.offset)
                    token1 := calldataload(add(data.offset, 0x20)) // 32 bytes after token0

                    // recipient is much further in the data structure, skipping several fields:
                    // - uint24 fee
                    // - int24 tickLower
                    // - int24 tickUpper
                    // - uint256 amount0Desired
                    // - uint256 amount1Desired
                    // - uint256 amount0Min
                    // - uint256 amount1Min
                    // - address recipient (need this)
                    // This calculation skips directly to the recipient which comes after the first 288 bytes
                    recipient := calldataload(add(data.offset, 0x120))
                }

                if (recipient != fund) revert UniswapV3Hooks_OnlyFund();
                if (!assetWhitelist[token0] || !assetWhitelist[token1]) {
                    revert UniswapV3Hooks_OnlyWhitelistedTokens();
                }
            } else if (selector == INonfungiblePositionManager.increaseLiquidity.selector) {
                uint256 tokenId;

                assembly {
                    tokenId := calldataload(data.offset)
                }

                _checkPosition(tokenId);
            } else if (selector == INonfungiblePositionManager.decreaseLiquidity.selector) {
                uint256 tokenId;

                assembly {
                    tokenId := calldataload(data.offset)
                }

                _checkPosition(tokenId);
            } else if (selector == INonfungiblePositionManager.collect.selector) {
                uint256 tokenId;

                assembly {
                    tokenId := calldataload(data.offset)
                }

                _checkPosition(tokenId);
            } else {
                revert UniswapV3Hooks_InvalidTargetSelector();
            }
        } else if (target == address(uniswapV3Router)) {
            if (
                selector == IUniswapRouter.exactInputSingle.selector
                    || selector == IUniswapRouter.exactOutputSingle.selector
            ) {
                address tokenIn;
                address tokenOut;
                address recipient;

                assembly {
                    // Skip the first 32 bytes (length of the ABI-encoded array) to get to the actual data.
                    // Since ExactInputSingleParams is tightly packed and follows the order:
                    // address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 deadline,
                    // uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96,
                    // we calculate offsets accordingly.
                    tokenIn := calldataload(data.offset)
                    tokenOut := calldataload(add(data.offset, 0x20)) // Offset by 32 bytes (0x20)
                    recipient := calldataload(add(data.offset, 0x60)) // Offset by 96 bytes (0x60)
                }

                if (!assetWhitelist[tokenIn] || !assetWhitelist[tokenOut]) {
                    revert UniswapV3Hooks_OnlyWhitelistedTokens();
                }

                if (recipient != fund) {
                    revert UniswapV3Hooks_OnlyFund();
                }
            } else {
                revert UniswapV3Hooks_InvalidTargetSelector();
            }
        } else {
            revert UniswapV3Hooks_InvalidTargetAddress();
        }
    }

    function checkAfterTransaction(
        address target,
        bytes4 selector,
        uint8,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override onlyFund {}

    function enableAsset(address asset) external onlyFund {
        if (
            asset == address(0) || asset == address(this) || asset == address(fund)
                || asset == address(uniswapV3PositionManager) || asset == address(uniswapV3Router)
        ) {
            revert UniswapV3Hooks_InvalidAsset();
        }

        assetWhitelist[asset] = true;

        emit UniswapV3Hooks_AssetEnabled(asset);
    }

    function disableAsset(address asset) external onlyFund {
        assetWhitelist[asset] = false;

        emit UniswapV3Hooks_AssetDisabled(asset);
    }
}
