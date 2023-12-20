// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {TransferHelper} from "@src/lib/TransferHelper.sol";
import {IUniswapV3PositionRouter} from "@src/interfaces/IUniswapV3PositionRouter.sol";
import {BaseRouter} from "@src/base/BaseRouter.sol";
import {IUniswapV3PoolActions} from "@src/interfaces/IUniswapV3PoolActions.sol";
import {PoolAddress} from "@src/lib/PoolAddress.sol";
import {FixedPoint128} from "@src/lib/FixedPoint128.sol";
import {FullMath} from "@src/lib/FullMath.sol";

/// @notice Does not support ETH to WETH as of right now
contract UniswapV3PositionRouter is BaseRouter, IUniswapV3PositionRouter {
    using PoolAddress for address;

    address public immutable uniswapV3Factory;
    mapping(bytes32 key => Position) public positions;

    constructor(address _owner, address _tokenWhitelistRegistry, address _uniswapV3Factory)
        BaseRouter(_owner, _tokenWhitelistRegistry)
    {
        uniswapV3Factory = _uniswapV3Factory;
    }

    function _positionKey(address owner, int24 tickLower, int24 tickUpper, address pool) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, tickLower, tickUpper, pool));
    }

    struct MintCallbackData {
        PoolAddress.PoolKey poolKey;
        address payer;
    }

    function mintLiquidity(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity
    ) external payable setCaller  returns(uint256 amount0, uint256 amount1) {
        _checkTokenIsWhitelisted(caller, token0);
        _checkTokenIsWhitelisted(caller, token1);

        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(token0, token1, fee);
        IUniswapV3PoolActions pool = IUniswapV3PoolActions(uniswapV3Factory.computeAddress(poolKey));

        MintCallbackData memory callback = MintCallbackData({poolKey: poolKey, payer: caller});

        // mint liquidity to the router
        (amount0, amount1) = pool.mint(address(this), tickLower, tickUpper, liquidity, abi.encode(callback));

        // update position liquidity
        bytes32 positionKey = _positionKey(caller, tickLower, tickUpper, address(pool));
        Position storage position = positions[positionKey];

        // if position doesn't exist, create it
        if(position.pool == address(0)) {
            positions[positionKey] = Position({
                pool: address(pool),
                liquidity: liquidity,
                feeGrowthInside0LastX128: 0,
                feeGrowthInside1LastX128: 0,
                tokensOwed0: 0,
                tokensOwed1: 0
            });
        } else {
            // else just update
            // this is now updated to the current transaction
            // (, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, , ) = pool.positions(positionKey);

            // position.tokensOwed0 += uint128(
            //     FullMath.mulDiv(
            //         feeGrowthInside0LastX128 - position.feeGrowthInside0LastX128,
            //         position.liquidity,
            //         FixedPoint128.Q128
            //     )
            // );
            // position.tokensOwed1 += uint128(
            //     FullMath.mulDiv(
            //         feeGrowthInside1LastX128 - position.feeGrowthInside1LastX128,
            //         position.liquidity,
            //         FixedPoint128.Q128
            //     )
            // );

            // position.feeGrowthInside0LastX128 = feeGrowthInside0LastX128;
            // position.feeGrowthInside1LastX128 = feeGrowthInside1LastX128;
            position.liquidity += liquidity;
        }
    }

    /// @notice Callback triggered by UniswapV3 pool upon minting
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

    function burnLiquidity(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower, 
        int24 tickUpper, 
        uint128 liquidity,
        uint256 amountMin0,
        uint256 amountMin1
    ) external setCaller returns(uint256 amountOwed0, uint256 amountOwed1) {
        require(liquidity > 0);
        _checkTokenIsWhitelisted(caller, token0);
        _checkTokenIsWhitelisted(caller, token1);

        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(token0, token1, fee);
        IUniswapV3PoolActions pool = IUniswapV3PoolActions(uniswapV3Factory.computeAddress(poolKey));

        Position storage position = positions[_positionKey(caller, tickLower, tickUpper, address(pool))];
        require(liquidity <= position.liquidity, "UniswapV3PositionRouter: INSUFFICIENT_LIQUIDITY");

        (amountOwed0, amountOwed1) = pool.burn(tickLower, tickUpper, liquidity);

        require(amountOwed0 >= amountMin0 && amountOwed1 >= amountMin1, "UniswapV3PositionRouter: PRICE_SLIPPAGE");

        // update position liquidity
        position.liquidity -= liquidity;
        position.tokensOwed0 += uint128(amountOwed0);
        position.tokensOwed1 += uint128(amountOwed1);
    }


    function collect(
        address token0,
        address token1,
        uint24 fee,
        int24 tickLower, 
        int24 tickUpper, 
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external setCaller returns (uint128 amount0, uint128 amount1){
        _checkTokenIsWhitelisted(caller, token0);
        _checkTokenIsWhitelisted(caller, token1);

        PoolAddress.PoolKey memory poolKey = PoolAddress.getPoolKey(token0, token1, fee);
        IUniswapV3PoolActions pool = IUniswapV3PoolActions(uniswapV3Factory.computeAddress(poolKey));

        Position storage position = positions[_positionKey(caller, tickLower, tickUpper, address(pool))];
        require(position.tokensOwed0 >= amount0Requested && position.tokensOwed1 >= amount1Requested, "UniswapV3PositionRouter: INSUFFICIENT_TOKENS_OWNED");

        (amount0, amount1) = pool.collect(caller, tickLower, tickUpper, amount0Requested, amount1Requested);

        position.tokensOwed0 -= amount0;
        position.tokensOwed1 -= amount1;
    }


}
