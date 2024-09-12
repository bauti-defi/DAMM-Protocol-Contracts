// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBeforeTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {BaseHook} from "@src/hooks/BaseHook.sol";
import {Errors} from "@src/libs/Errors.sol";
import "@src/libs/Constants.sol";

error AaveV3CallValidator_OnlyWhitelistedTokens();
error AaveV3CallValidator_InvalidAsset();
error AaveV3CallValidator_FundMustBeRecipient();

event AaveV3CallValidator_AssetEnabled(address asset);

event AaveV3CallValidator_AssetDisabled(address asset);

contract AaveV3CallValidator is BaseHook, IBeforeTransaction {
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
    ) external override onlyFund expectOperation(operation, CALL) {
        if (target != address(aaveV3Pool)) {
            revert Errors.Hook_InvalidTargetAddress();
        }

        address asset;
        address onBehalfOf;

        if (selector == L1_SUPPLY_SELECTOR || selector == L1_WITHDRAW_SELECTOR) {
            assembly {
                asset := calldataload(data.offset)
                onBehalfOf := calldataload(add(data.offset, 0x40))
            }
        } else {
            revert Errors.Hook_InvalidTargetSelector();
        }

        if (!assetWhitelist[asset]) {
            revert AaveV3CallValidator_OnlyWhitelistedTokens();
        }
        if (onBehalfOf != address(fund)) {
            revert AaveV3CallValidator_FundMustBeRecipient();
        }
    }

    function enableAsset(address asset) external onlyFund {
        if (
            asset == address(0) || asset == address(fund) || asset == address(this)
                || asset == address(aaveV3Pool)
        ) {
            revert AaveV3CallValidator_InvalidAsset();
        }

        assetWhitelist[asset] = true;

        emit AaveV3CallValidator_AssetEnabled(asset);
    }

    function disableAsset(address asset) external onlyFund {
        assetWhitelist[asset] = false;

        emit AaveV3CallValidator_AssetDisabled(asset);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IBeforeTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
