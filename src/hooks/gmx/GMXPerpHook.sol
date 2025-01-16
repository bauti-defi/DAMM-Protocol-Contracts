// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {BaseHook} from "@src/hooks/BaseHook.sol";
import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@gmx/callback/IOrderCallbackReceiver.sol";
import {
    IExchangeRouter, IBaseOrderUtils, IGMXRouter
} from "@src/interfaces/external/IGMXRouter.sol";
import "@src/libs/Constants.sol";

error GMXPerpHook_InvalidInteraction();
error GMXPerpHook_InvalidCaller();
error GMXPerpHook_UnsupportedAction();
error GMXPerpHook_InvalidReceiver();
error GMXPerpHook_InvalidOrderCancellationReceiver();
error GMXPerpHook_InvalidCallbackContract();

event GMXPerpHookGMXPerpHook_InteractionEnabled(
    address market,
    address initialCollateralToken,
    address[] swapPath,
    Order.OrderType orderType,
    bool shouldUnwrapNativeToken,
    bool isLong,
    bytes32 interactionIdentifier
);

event GMXPerpHook_InteractionDisabled(bytes32 interactionIdentifier);

contract GMXPerpHook is BaseHook, IBeforeTransaction, IAfterTransaction, IOrderCallbackReceiver {
    mapping(bytes32 key => bool enabled) public gmxInteractionWhitelist;
    address public immutable gmxRouter;
    address public immutable gmxOrderHandler;
    address public immutable gmxProxy;

    constructor(address _fund, address _gmxRouter, address _gmxOrderHandler, address _gmxProxy)
        BaseHook(_fund)
    {
        gmxRouter = _gmxRouter;
        gmxOrderHandler = _gmxOrderHandler;
        gmxProxy = _gmxProxy;
    }

    modifier onlyGmxOrderHandler() {
        if (msg.sender != gmxOrderHandler) {
            revert GMXPerpHook_InvalidCaller();
        }
        _;
    }

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data
    ) external view override onlyFund {
        if (selector == IGMXRouter.createOrder.selector) {
            _validateTargetAndCallType(target, gmxProxy, operation, DELEGATE_CALL);

            _parseAndValidateCreateOrder(data);
        } else if (selector == IGMXRouter.cancelOrder.selector) {
            _validateTargetAndCallType(target, gmxRouter, operation, CALL);

            _parseAndValidatePositionKey(data);
        } else if (selector == IGMXRouter.updateOrder.selector) {
            _validateTargetAndCallType(target, gmxProxy, operation, DELEGATE_CALL);

            /// TODO: this is not validating everything correctly!
            _parseAndValidatePositionKey(data);
        } else if (selector == IGMXRouter.claimFundingFees.selector) {
            _validateTargetAndCallType(target, gmxRouter, operation, CALL);

            _parseAndValidateClaimFunding(data);
        } else {
            revert Errors.Hook_InvalidTargetSelector();
        }
    }

    function checkAfterTransaction(
        address,
        bytes4 selector,
        uint8,
        uint256,
        bytes calldata,
        bytes calldata returnData
    ) external override onlyFund {
        if (selector == IExchangeRouter.createOrder.selector) {
            bytes32 key = abi.decode(returnData, (bytes32));
            fund.onPositionOpened(_positionPointer(key));
        }
    }

    function afterOrderExecution(bytes32 key, Order.Props memory, EventUtils.EventLogData memory)
        external
        override
        onlyGmxOrderHandler
    {
        fund.onPositionOpened(_positionPointer(key));
    }

    function afterOrderCancellation(bytes32 key, Order.Props memory, EventUtils.EventLogData memory)
        external
        override
        onlyGmxOrderHandler
    {
        fund.onPositionClosed(_positionPointer(key));
    }

    function afterOrderFrozen(bytes32, Order.Props memory, EventUtils.EventLogData memory)
        external
        pure
        override
    {
        revert GMXPerpHook_UnsupportedAction();
    }

    function _validateTargetAndCallType(
        address target,
        address expectedTarget,
        uint8 operation,
        uint8 expectedOperation
    ) internal pure {
        if (target != expectedTarget) {
            revert Errors.Hook_InvalidTargetAddress();
        } else if (operation != expectedOperation) {
            revert Errors.Hook_InvalidOperation();
        }
    }

    function _positionPointer(bytes32 key) internal pure returns (bytes32) {
        return keccak256(abi.encode(key, type(IExchangeRouter).interfaceId));
    }

    /// @dev possible CreateOrderParams config settings:
    /// - addresses.callbackContract
    /// - addresses.market
    /// - addresses.initialCollateralToken
    /// - orderType
    /// - addresses.swapPath
    /// - shouldUnwrapNativeToken
    /// - isLong
    function _gmxInteractionIdentifier(
        address market,
        address initialCollateralToken,
        address[] memory swapPath,
        Order.OrderType orderType,
        bool shouldUnwrapNativeToken,
        bool isLong
    ) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                market, initialCollateralToken, swapPath, orderType, shouldUnwrapNativeToken, isLong
            )
        );
    }

    function _parseAndValidateCreateOrder(bytes calldata data) internal view {
        IBaseOrderUtils.CreateOrderParams memory params =
            abi.decode(data, (IBaseOrderUtils.CreateOrderParams));

        if (params.addresses.receiver != address(fund)) {
            revert GMXPerpHook_InvalidReceiver();
        }

        if (params.addresses.cancellationReceiver != address(fund)) {
            revert GMXPerpHook_InvalidOrderCancellationReceiver();
        }

        if (params.addresses.callbackContract != address(this)) {
            revert GMXPerpHook_InvalidCallbackContract();
        }

        bytes32 interactionIdentifier = _gmxInteractionIdentifier(
            params.addresses.market,
            params.addresses.initialCollateralToken,
            params.addresses.swapPath,
            params.orderType,
            params.shouldUnwrapNativeToken,
            params.isLong
        );

        if (!gmxInteractionWhitelist[interactionIdentifier]) {
            revert GMXPerpHook_InvalidInteraction();
        }
    }

    function _parseAndValidatePositionKey(bytes calldata data) internal view {
        bytes32 key = abi.decode(data, (bytes32));

        if (!fund.holdsPosition(_positionPointer(key))) {
            revert GMXPerpHook_InvalidInteraction();
        }
    }

    function _parseAndValidateClaimFunding(bytes calldata data) internal view {
        (address[] memory markets, address[] memory tokens, address receiver) =
            abi.decode(data, (address[], address[], address));

        if (receiver != address(fund)) {
            revert GMXPerpHook_InvalidReceiver();
        }
    }

    function enableGmxInteraction(
        address market,
        address initialCollateralToken,
        address[] memory swapPath,
        Order.OrderType orderType,
        bool shouldUnwrapNativeToken,
        bool isLong
    ) external onlyFund {
        bytes32 interactionIdentifier = _gmxInteractionIdentifier(
            market, initialCollateralToken, swapPath, orderType, shouldUnwrapNativeToken, isLong
        );

        gmxInteractionWhitelist[interactionIdentifier] = true;

        emit GMXPerpHookGMXPerpHook_InteractionEnabled(
            market,
            initialCollateralToken,
            swapPath,
            orderType,
            shouldUnwrapNativeToken,
            isLong,
            interactionIdentifier
        );
    }

    function disableGmxInteraction(bytes32 interactionIdentifier) external onlyFund {
        gmxInteractionWhitelist[interactionIdentifier] = false;

        emit GMXPerpHook_InteractionDisabled(interactionIdentifier);
    }
}
