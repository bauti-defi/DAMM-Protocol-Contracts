// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFund} from "@src/interfaces/IFund.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IFundFactory} from "@src/interfaces/IFundFactory.sol";
import {FundCallbackHandler} from "@src/FundCallbackHandler.sol";
import "@src/libs/Errors.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address singleton, bytes memory initializerPayload, uint256 nonce)
        external
        returns (address);
}

/// @dev Factory contract for deploying funds
contract FundFactory is IFundFactory {
    /// @dev variable declaration order is important for delegate call back in to work
    bool private deploying;
    uint256 private nonce;

    modifier lock() {
        if (deploying) revert Errors.FundFactory_DeploymentLockViolated();
        deploying = true;
        _;
        deploying = false;
    }

    /// this should be a delegate call from the fund right after creation.
    function fundDeploymentCallback() external override {
        if (!deploying) revert Errors.FundFactory_DeploymentLockViolated();

        /// instantiate fresh callback handler for each fund
        FundCallbackHandler handler = new FundCallbackHandler(address(this));
        /// set the fallback handler on the fund
        IFund(address(this)).setFallbackHandler(address(handler));
    }

    function _deployFund(
        address safeProxyFactory,
        address safeSingleton,
        address[] memory admins,
        uint256 threshold
    ) internal lock returns (IFund) {
        /// create callback payload
        bytes memory callbackPayload =
            abi.encodeWithSelector(IFundFactory.fundDeploymentCallback.selector);

        /// create gnosis safe initializer payload
        bytes memory initializerPayload = abi.encodeWithSelector(
            ISafe.setup.selector,
            /// fund admins
            admins,
            /// multisig signer threshold
            threshold,
            /// @notice callback target is this factory
            address(this),
            /// @notice callback data is the callback payload
            callbackPayload,
            /// @notice dont include for now, will be set in the callback
            address(0),
            /// no payment token
            address(0),
            /// payment amount
            0,
            /// payment receiver
            payable(address(0))
        );

        address payable fund = payable(
            address(
                ISafeProxyFactory(safeProxyFactory).createProxyWithNonce(
                    safeSingleton, initializerPayload, ++nonce
                )
            )
        );

        return IFund(fund);
    }

    function deployFund(
        address safeProxyFactory,
        address safeSingleton,
        address[] memory admins,
        uint256 threshold
    ) external returns (IFund fund) {
        /// deploy the fund
        fund = _deployFund(safeProxyFactory, safeSingleton, admins, threshold);

        emit FundDeployed(address(fund), msg.sender, admins, threshold, safeSingleton);
    }
}
