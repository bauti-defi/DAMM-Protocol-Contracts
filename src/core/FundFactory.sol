// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {IFund} from "@src/interfaces/IFund.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IFundFactory} from "@src/interfaces/IFundFactory.sol";
import {FundCallbackHandler} from "./FundCallbackHandler.sol";
import "@src/libs/Errors.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializerPayload, uint256 nonce)
        external
        returns (address);
}

/// @title FundFactory
/// @notice Implementation of IFundFactory for deploying Safe-based investment funds
/// @dev Uses Safe's proxy factory for deterministic deployments and handles callback initialization
contract FundFactory is IFundFactory {
    /// @notice Address of this contract, used for delegatecall checks
    address private immutable self;

    /// @notice Deployment lock to prevent reentrant calls
    /// @dev Variable declaration order is important for delegate call back in to work
    bool private deploying;

    /// @notice Prevents reentrant calls during fund deployment
    modifier lock() {
        if (deploying) revert Errors.FundFactory_DeploymentLockViolated();
        deploying = true;
        _;
        deploying = false;
    }

    /// @notice Ensures function is called via delegatecall
    modifier isDelegateCall() {
        if (address(this) == self) revert Errors.FundFactory_OnlyDelegateCall();
        _;
    }

    constructor() {
        self = address(this);
    }

    /// @inheritdoc IFundFactory
    function convertSafeToFund() external lock isDelegateCall {
        /// instantiate fresh callback handler for each fund
        FundCallbackHandler handler = new FundCallbackHandler(address(this));
        /// set the fallback handler on the fund
        IFund(address(this)).setFallbackHandler(address(handler));
    }

    /// @inheritdoc IFundFactory
    function fundDeploymentCallback() external override {
        if (!deploying) revert Errors.FundFactory_DeploymentLockViolated();

        /// instantiate fresh callback handler for each fund
        FundCallbackHandler handler = new FundCallbackHandler(address(this));
        /// set the fallback handler on the fund
        IFund(address(this)).setFallbackHandler(address(handler));
    }

    /// @notice Internal implementation of fund deployment
    /// @dev Protected by lock modifier to prevent reentrant calls
    function _deployFund(
        address safeProxyFactory,
        address safeSingleton,
        address[] memory admins,
        uint256 nonce,
        uint256 threshold
    ) internal lock returns (IFund) {
        /// create callback payload
        bytes memory callbackPayload =
            abi.encodeWithSelector(IFundFactory.fundDeploymentCallback.selector);

        /// create gnosis safe initializer payload
        bytes memory initializerPayload = abi.encodeWithSelector(
            ISafe.setup.selector,
            admins,
            threshold,
            address(this),
            callbackPayload,
            address(0),
            address(0),
            0,
            payable(address(0))
        );

        address payable fund = payable(
            address(
                ISafeProxyFactory(safeProxyFactory).createProxyWithNonce(
                    safeSingleton, initializerPayload, nonce
                )
            )
        );

        return IFund(fund);
    }

    /// @inheritdoc IFundFactory
    function deployFund(
        address safeProxyFactory,
        address safeSingleton,
        address[] memory admins,
        uint256 nonce,
        uint256 threshold
    ) external returns (IFund fund) {
        fund = _deployFund(safeProxyFactory, safeSingleton, admins, nonce, threshold);
        emit FundDeployed(address(fund), msg.sender, admins, threshold, safeSingleton);
    }
}
