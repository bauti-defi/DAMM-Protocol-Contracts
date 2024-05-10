// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@safe-contracts/handler/TokenCallbackHandler.sol";
import "@safe-contracts/handler/HandlerContext.sol";
import "@openzeppelin-contracts/utils/structs/EnumerableSet.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";

event PositionOpened(address indexed by, bytes32 positionPointer);

event PositionClosed(address indexed by, bytes32 positionPointer);

error NotModule();

/// @dev concept under development!
contract FundCallbackHandler is TokenCallbackHandler, HandlerContext, IPortfolio {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    address public immutable fund;

    /// could be used to hold fund specific state
    /// for example, registry of open positions, allowed tokens
    /// maybe hook registry needs to go here?
    /// maybe pause state should go here?
    /// maybe only global state should go here?

    /// should only be truly global variables. nothing module specific.
    /// `pause` is a good place to start
    /// hooks registry here would be a bad idea

    EnumerableSet.Bytes32Set private openPositions;

    constructor(address _fund) {
        fund = _fund;
    }

    modifier onlyModule() {
        if (!ISafe(fund).isModuleEnabled(msg.sender)) revert NotModule();
        _;
    }

    function onPositionOpened(bytes32 positionPointer) external onlyModule returns (bool result) {
        result = openPositions.add(positionPointer);

        emit PositionOpened(msg.sender, positionPointer);
    }

    function onPositionClosed(bytes32 positionPointer) external onlyModule returns (bool result) {
        result = openPositions.remove(positionPointer);

        emit PositionClosed(msg.sender, positionPointer);
    }

    function holdsPosition(bytes32 positionPointer) external view returns (bool) {
        return openPositions.contains(positionPointer);
    }

    function hasOpenPositions() external view returns (bool) {
        return openPositions.length() > 0;
    }
}
