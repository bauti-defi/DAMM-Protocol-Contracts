// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// import {IExchangeRouter, IBaseOrderUtils} from "@src/interfaces/external/IGMXRouter.sol";
// import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
// import {Errors} from "@src/libs/Errors.sol";

// contract GMXProxy {
//     using SafeERC20 for IERC20;

//     address private immutable self;

//     address public immutable gmxRouter;
//     address public immutable gmxOrderVault;
//     address public immutable wnt;

//     constructor(address _gmxRouter, address _gmxOrderVault, address _wnt) {
//         self = address(this);

//         gmxRouter = _gmxRouter;
//         gmxOrderVault = _gmxOrderVault;
//         wnt = _wnt;
//     }

//     modifier isDelegateCall() {
//         if (address(this) == self) revert Errors.OnlyDelegateCall();
//         _;
//     }

//     function createOrder(IBaseOrderUtils.CreateOrderParams calldata params)
//         external
//         payable
//         isDelegateCall
//         returns (bytes32)
//     {
//         IERC20(params.addresses.initialCollateralToken).safeTransfer(
//             gmxOrderVault, params.numbers.initialCollateralDeltaAmount
//         );
//         IERC20(wnt).safeTransfer(gmxRouter, params.numbers.executionFee);

//         if (msg.value > 0) {
//             gmxOrderVault.call{value: msg.value}("");
//         }

//         return IExchangeRouter(gmxRouter).createOrder(params);
//     }

//     function updateOrder(
//         bytes32 key,
//         uint256 sizeDeltaUsd,
//         uint256 acceptablePrice,
//         uint256 triggerPrice,
//         uint256 minOutputAmount,
//         uint256 validFromTime,
//         bool autoCancel,
//         uint256 executionFee
//     ) external payable isDelegateCall {
//         IERC20(wnt).safeTransfer(gmxRouter, executionFee);

//         if (msg.value > 0) {
//             gmxOrderVault.call{value: msg.value}("");
//         }

//         IExchangeRouter(gmxRouter).updateOrder(
//             key,
//             sizeDeltaUsd,
//             acceptablePrice,
//             triggerPrice,
//             minOutputAmount,
//             validFromTime,
//             autoCancel
//         );
//     }
// }
