// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import "@src/hooks/BaseHook.sol";
import "@src/libs/Constants.sol";

error AaveV3Hooks_OnlyWhitelistedTokens();
error AaveV3Hooks_InvalidAsset();
error AaveV3Hooks_PositionApertureFailed();
error AaveV3Hooks_PositionClosureFailed();
error AaveV3Hooks_FundMustBeRecipient();

event AaveV3Hooks_AssetEnabled(address asset);

event AaveV3Hooks_AssetDisabled(address asset);

contract AaveV3Hooks is BaseHook, IBeforeTransaction, IAfterTransaction {
    bytes32 constant POSITION_POINTER = keccak256("aave.v3.hooks");

    bytes4 constant L1_WITHDRAW_SELECTOR = IPool.withdraw.selector;
    bytes4 constant L1_SUPPLY_SELECTOR = IPool.supply.selector;

    IPool public immutable aaveV3Pool;

    mapping(address asset => bool whitelisted) public assetWhitelist;

    constructor(address _fund, address _aaveV3Pool) BaseHook(_fund) {
        aaveV3Pool = IPool(_aaveV3Pool);
    }

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata data
    ) external view override onlyFund expectOperation(operation, CALL) {
        if (target != address(aaveV3Pool)) {
            revert Errors.Hook_InvalidTargetAddress();
        }

        address asset;
        address onBehalfOf;

        if (selector == L1_SUPPLY_SELECTOR) {
            assembly {
                asset := calldataload(data.offset)
                onBehalfOf := calldataload(add(data.offset, 0x40))
            }
        } else if (selector == L1_WITHDRAW_SELECTOR) {
            assembly {
                asset := calldataload(data.offset)
                onBehalfOf := calldataload(add(data.offset, 0x40))
            }
        } else {
            revert Errors.Hook_InvalidTargetSelector();
        }

        if (!assetWhitelist[asset]) {
            revert AaveV3Hooks_OnlyWhitelistedTokens();
        }
        if (onBehalfOf != address(fund)) {
            revert AaveV3Hooks_FundMustBeRecipient();
        }
    }

    function checkAfterTransaction(
        address target,
        bytes4 selector,
        uint8 operation,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override onlyFund expectOperation(operation, CALL) {
        if (target != address(aaveV3Pool)) {
            revert Errors.Hook_InvalidTargetAddress();
        }

        if (selector == L1_SUPPLY_SELECTOR) {
            /// @dev open position if not already open
            /// that means all open aave positions are represented by a single pointer
            if (!fund.holdsPosition(POSITION_POINTER)) {
                if (!fund.onPositionOpened(POSITION_POINTER)) {
                    revert AaveV3Hooks_PositionApertureFailed();
                }
            }
        } else if (selector == L1_WITHDRAW_SELECTOR) {
            (uint256 collateralDeposited,,,,,) = aaveV3Pool.getUserAccountData(address(fund));
            if (collateralDeposited == 0) {
                if (!fund.onPositionClosed(POSITION_POINTER)) {
                    revert AaveV3Hooks_PositionClosureFailed();
                }
            }
        }
    }

    function enableAsset(address asset) external onlyFund {
        if (
            asset == address(0) || asset == address(fund) || asset == address(this)
                || asset == address(aaveV3Pool)
        ) {
            revert AaveV3Hooks_InvalidAsset();
        }

        assetWhitelist[asset] = true;

        emit AaveV3Hooks_AssetEnabled(asset);
    }

    function disableAsset(address asset) external onlyFund {
        assetWhitelist[asset] = false;

        emit AaveV3Hooks_AssetDisabled(asset);
    }
}
