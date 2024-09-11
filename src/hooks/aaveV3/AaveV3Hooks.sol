// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {BaseHook} from "@src/hooks/BaseHook.sol";
import {Errors} from "@src/libs/Errors.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@src/libs/Constants.sol";

error AaveV3Hooks_OnlyWhitelistedTokens();
error AaveV3Hooks_InvalidAsset();
error AaveV3Hooks_FundMustBeRecipient();
error AaveV3Hooks_ATokenBalanceCheckFailed();

event AaveV3Hooks_AssetEnabled(address asset);

event AaveV3Hooks_AssetDisabled(address asset);

contract AaveV3Hooks is BaseHook, IBeforeTransaction, IAfterTransaction {
    bytes4 constant L1_WITHDRAW_SELECTOR = IPool.withdraw.selector;
    bytes4 constant L1_SUPPLY_SELECTOR = IPool.supply.selector;
    bytes4 constant ERC20_BALANCE_OF_SELECTOR = IERC20.balanceOf.selector;

    IPool public immutable aaveV3Pool;

    mapping(address asset => bool whitelisted) public assetWhitelist;

    constructor(address _fund, address _aaveV3Pool) BaseHook(_fund) {
        aaveV3Pool = IPool(_aaveV3Pool);
    }

    function createPositionPointer(address asset) internal pure returns (bytes32 pointer) {
        pointer = keccak256(abi.encodePacked(asset, type(IPool).interfaceId));
    }

    function getATokenFundBalance(address asset) private view returns (uint256) {
        address aTokenAddress = aaveV3Pool.getReserveData(asset).aTokenAddress;
        (bool success, bytes memory data) = aTokenAddress.staticcall(
            abi.encodeWithSelector(ERC20_BALANCE_OF_SELECTOR, address(fund))
        );
        if (!success) {
            revert AaveV3Hooks_ATokenBalanceCheckFailed();
        }
        return abi.decode(data, (uint256));
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

        if (selector == L1_SUPPLY_SELECTOR) {
            assembly {
                asset := calldataload(data.offset)
                onBehalfOf := calldataload(add(data.offset, 0x40))
            }

            /// optimisitically open the position on the fund
            /// @notice this is a no-op if the position is already opened
            fund.onPositionOpened(createPositionPointer(asset));
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
        bytes calldata data,
        bytes calldata
    ) external override onlyFund expectOperation(operation, CALL) {
        if (target != address(aaveV3Pool)) {
            revert Errors.Hook_InvalidTargetAddress();
        }

        if (selector == L1_WITHDRAW_SELECTOR) {
            address asset;
            assembly {
                asset := calldataload(data.offset)
            }

            uint256 balance = getATokenFundBalance(asset);
            /// if the balance is 0, then the position should be closed
            if (balance == 0) {
                /// @notice this is a no-op if the position is already closed
                fund.onPositionClosed(createPositionPointer(asset));
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

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IBeforeTransaction).interfaceId
            || interfaceId == type(IAfterTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
