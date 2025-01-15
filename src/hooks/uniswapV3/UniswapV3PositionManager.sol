// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {INonfungiblePositionManager} from "@src/interfaces/external/INonfungiblePositionManager.sol";
import {BaseHook} from "@src/hooks/BaseHook.sol";
import {CALL} from "@src/libs/Constants.sol";

contract UniswapV3PositionManager is BaseHook, IAfterTransaction {
    INonfungiblePositionManager public immutable uniswapV3PositionManager;

    constructor(address _fund, address _uniswapV3PositionManager) BaseHook(_fund) {
        uniswapV3PositionManager = INonfungiblePositionManager(_uniswapV3PositionManager);
    }

    function isPositionEmpty(uint256 tokenId) internal view returns (bool) {
        (,,,,,,, uint128 liquidity,,, uint128 token0Owed, uint128 token1Owed) =
            uniswapV3PositionManager.positions(tokenId);
        return liquidity == 0 && token0Owed == 0 && token1Owed == 0;
    }

    function createPositionPointer(uint256 tokenId) internal pure returns (bytes32 pointer) {
        pointer =
            keccak256(abi.encodePacked(tokenId, type(INonfungiblePositionManager).interfaceId));
    }

    function checkAfterTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data,
        bytes calldata returnData
    ) external override onlyFund expectOperation(operation, CALL) {
        if (target == address(uniswapV3PositionManager)) {
            if (selector == INonfungiblePositionManager.mint.selector) {
                uint256 tokenId;
                uint128 liquidity;
                assembly {
                    tokenId := calldataload(returnData.offset)
                    liquidity := calldataload(add(returnData.offset, 0x20))
                }

                /// if liquidity is not 0, the position was opened
                if (liquidity > 0) {
                    /// @notice this is a no-op if the position is already closed
                    fund.onPositionOpened(createPositionPointer(tokenId));
                }
            } else if (selector == INonfungiblePositionManager.collect.selector) {
                uint256 tokenId;

                assembly {
                    tokenId := calldataload(data.offset)
                }

                if (isPositionEmpty(tokenId)) {
                    /// @notice this is a no-op if the position is already closed
                    fund.onPositionClosed(createPositionPointer(tokenId));
                }
            } else if (selector == INonfungiblePositionManager.increaseLiquidity.selector) {
                uint256 tokenId;
                uint128 liquidity;
                assembly {
                    tokenId := calldataload(data.offset)
                    liquidity := calldataload(returnData.offset)
                }

                /// if liquidity is not 0, the position was opened
                if (liquidity > 0) {
                    /// @notice this is a no-op if the position is already opened
                    fund.onPositionOpened(createPositionPointer(tokenId));
                }
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAfterTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
