// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IExchangeRouter, IBaseOrderUtils} from "@gmx/router/IExchangeRouter.sol";

interface IGMXRouter {
    function claimCollateral(
        address[] memory markets,
        address[] memory tokens,
        uint256[] memory timeKeys,
        address receiver
    ) external payable returns (uint256[] memory);

    /**
     * @dev Claims funding fees for the given markets and tokens on behalf of the caller, and sends the
     * fees to the specified receiver. The length of the `markets` and `tokens` arrays must be the same.
     * For each market-token pair, the `claimFundingFees()` function in the `MarketUtils` contract is
     * called to claim the fees for the caller.
     *
     * @param markets An array of market addresses
     * @param tokens An array of token addresses, corresponding to the given markets
     * @param receiver The address to which the claimed fees should be sent
     */
    function claimFundingFees(address[] memory markets, address[] memory tokens, address receiver)
        external
        payable
        returns (uint256[] memory);

    /**
     * @dev Claims affiliate rewards for the given markets and tokens on behalf of the caller, and sends
     * the rewards to the specified receiver. The length of the `markets` and `tokens` arrays must be
     * the same. For each market-token pair, the `claimAffiliateReward()` function in the `ReferralUtils`
     * contract is called to claim the rewards for the caller.
     *
     * @param markets An array of market addresses
     * @param tokens An array of token addresses, corresponding to the given markets
     * @param receiver The address to which the claimed rewards should be sent
     */
    function claimAffiliateRewards(
        address[] memory markets,
        address[] memory tokens,
        address receiver
    ) external payable returns (uint256[] memory);

    function updateOrder(
        bytes32 key,
        uint256 sizeDeltaUsd,
        uint256 acceptablePrice,
        uint256 triggerPrice,
        uint256 minOutputAmount,
        uint256 validFromTime,
        bool autoCancel,
        uint256 executionFee
    ) external payable;

    function cancelOrder(bytes32 key) external payable;

    function createOrder(IBaseOrderUtils.CreateOrderParams calldata params)
        external
        payable
        returns (bytes32);
}
