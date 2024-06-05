// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@src/interfaces/external/AggregatorV3Interface.sol";

address constant ARB_USDT_USD_FEED = 0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7;
address constant ARB_USDC_USD_FEED = 0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3;
address constant ARB_DAI_USD_FEED = 0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB;

AggregatorV3Interface constant USDT_USD_FEED = AggregatorV3Interface(ARB_USDT_USD_FEED);
AggregatorV3Interface constant USDC_USD_FEED = AggregatorV3Interface(ARB_USDC_USD_FEED);
AggregatorV3Interface constant DAI_USD_FEED = AggregatorV3Interface(ARB_DAI_USD_FEED);
