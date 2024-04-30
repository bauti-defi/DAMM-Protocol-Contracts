// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";
import {IUniswapRouter} from "@src/interfaces/external/IUniswapRouter.sol";
import {IERC721} from "@openzeppelin-contracts/token/ERC721/IERC721.sol";

error OnlyFund();
error OnlyWhitelistedTokens();

contract UniswapV3Hooks is IBeforeTransaction {
    address public immutable fund;
    INonfungiblePositionManager public immutable uniswapV3PositionManager;
    address public immutable uniswapV3Router;

    mapping(address asset => bool whitelisted) public assetWhitelist;

    constructor(address _fund, address _uniswapV3PositionManager, address _uniswapV3Router) {
        fund = _fund;
        uniswapV3PositionManager = INonfungiblePositionManager(_uniswapV3PositionManager);
        uniswapV3Router = _uniswapV3Router;
    }

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8,
        uint256,
        bytes memory data
    ) external view override {
        if (msg.sender != fund) revert OnlyFund();

        if (target == address(uniswapV3PositionManager)) {
            if (selector == INonfungiblePositionManager.mint.selector) {
                INonfungiblePositionManager.MintParams memory params =
                    abi.decode(data, (INonfungiblePositionManager.MintParams));

                if (params.recipient != fund) revert OnlyFund();
                if (!assetWhitelist[params.token0] || !assetWhitelist[params.token1]) {
                    revert OnlyWhitelistedTokens();
                }
            } else if (selector == INonfungiblePositionManager.increaseLiquidity.selector) {
                INonfungiblePositionManager.IncreaseLiquidityParams memory params =
                    abi.decode(data, (INonfungiblePositionManager.IncreaseLiquidityParams));

                require(
                    IERC721(address(uniswapV3PositionManager)).ownerOf(params.tokenId) == fund,
                    "not owned by fund"
                );
                // get the position information
                (,, address token0, address token1,,,,,,,,) =
                    uniswapV3PositionManager.positions(params.tokenId);

                if (!assetWhitelist[token0] || !assetWhitelist[token1]) {
                    revert OnlyWhitelistedTokens();
                }
            } else if (selector == INonfungiblePositionManager.decreaseLiquidity.selector) {} else {
                revert("unsupported selector");
            }
        } else if (target == uniswapV3Router) {} else {
            revert("unsupported target");
        }
    }

    function enableAsset(address asset) external {
        require(msg.sender == fund, "only fund");
        assetWhitelist[asset] = true;
    }

    function disableAsset(address asset) external {
        require(msg.sender == fund, "only fund");
        assetWhitelist[asset] = false;
    }
}
