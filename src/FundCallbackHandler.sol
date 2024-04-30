// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@safe-contracts/handler/TokenCallbackHandler.sol";
import "@safe-contracts/handler/HandlerContext.sol";

/// @dev concept under development!
contract FundCallbackHandler is TokenCallbackHandler, HandlerContext {
    address public immutable fund;

    /// could be used to hold fund specific state
    /// for example, registry of open positions, allowed tokens
    /// maybe hook registry needs to go here?
    /// maybe pause state should go here?
    /// maybe only global state should go here?

    mapping(address asset => bool enabled) public managedAssets;

    constructor(address _fund) {
        fund = _fund;
    }
}
