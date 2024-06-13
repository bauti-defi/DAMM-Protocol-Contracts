// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IFund} from "@src/interfaces/IFund.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {IFundFactory} from "@src/interfaces/IFundFactory.sol";
import {FundCallbackHandler} from "@src/FundCallbackHandler.sol";

interface ISafeProxyFactory {
    function createProxyWithNonce(address, bytes memory, uint256) external returns (address);
}

event FundDeployed(
    address indexed fund,
    address deployer,
    address[] admins,
    uint256 threshold,
    address safeSingleton
);

contract FundFactory is IFundFactory {
    bool private deploying;

    // this should be a delegate call from the fund right after creation.
    function fundDeploymentCallback() external override {
        require(deploying, "Not Deploying");
        FundCallbackHandler handler = new FundCallbackHandler(address(this));
        IFund(address(this)).setFallbackHandler(address(handler));
    }

    function _deployFund(
        address safeProxyFactory,
        address safeSingleton,
        address[] memory admins,
        uint256 threshold
    ) internal returns (IFund) {
        // create callback payload
        bytes memory callbackPayload =
            abi.encodeWithSelector(IFundFactory.fundDeploymentCallback.selector);

        // create gnosis safe initializer payload
        bytes memory initializerPayload = abi.encodeWithSelector(
            ISafe.setup.selector,
            admins, // fund admins
            threshold, // multisig signer threshold
            address(this), // to
            callbackPayload, // data
            address(0), // dont include for now, will be added in the callback
            address(0), // payment token
            0, // payment amount
            payable(address(0)) // payment receiver
        );

        address payable fund = payable(
            address(
                ISafeProxyFactory(safeProxyFactory).createProxyWithNonce(
                    safeSingleton, initializerPayload, 1
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
        require(deploying == false, "Already deploying");

        deploying = true;

        // deploy the fund
        fund = _deployFund(safeProxyFactory, safeSingleton, admins, threshold);

        deploying = false;

        emit FundDeployed(address(fund), msg.sender, admins, threshold, safeSingleton);
    }
}
