// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "@src/lib/TransferHelper.sol";
import {IUniswapV3PositionRouter} from "@src/interfaces/IUniswapV3PositionRouter.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";
import {IUniswapV3PoolActions} from "@src/interfaces/IUniswapV3PoolActions.sol";
import {PoolAddress} from "@src/lib/PoolAddress.sol";

/// @notice Does not support ETH to WETH as of right now
contract UniswapV3PositionRouter is BaseRouter, IUniswapV3PositionRouter {
    using PoolAddress for address;

    address public immutable uniswapV3Factory;

    constructor(address _owner, address _tokenWhitelistRegistry, address _uniswapV3Factory)
        BaseRouter(_owner, _tokenWhitelistRegistry)
    {
        uniswapV3Factory = _uniswapV3Factory;
    }

    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    function mintPosition(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external payable setCaller {
        _checkTokenIsWhitelisted(caller, token0);
        _checkTokenIsWhitelisted(caller, token1);

        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(token0, token1, fee);
        IUniswapV3PoolActions pool = IUniswapV3PoolActions(uniswapV3Factory.computeAddress(poolKey));

        MintCallbackData memory callback = MintCallbackData({poolKey: poolKey, payer: caller});

        pool.mint(caller, tickLower, tickUpper, liquidity, abi.encode(callback));
    }

    function uniswapV3MintCallback(uint256 amount0Owed, uint256 amount1Owed, bytes calldata data) external {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));
        require(
            msg.sender == PoolAddress.computeAddress(uniswapV3Factory, decoded.poolKey),
            "UniswapV3PositionRouter: INVALID_POOL"
        );

        if (amount0Owed > 0) {
            _checkTokenIsWhitelisted(decoded.payer, decoded.poolKey.token0);
            TransferHelper.safeTransferFrom(decoded.poolKey.token0, decoded.payer, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            _checkTokenIsWhitelisted(decoded.payer, decoded.poolKey.token1);
            TransferHelper.safeTransferFrom(decoded.poolKey.token1, decoded.payer, msg.sender, amount1Owed);
        }
    }
}
