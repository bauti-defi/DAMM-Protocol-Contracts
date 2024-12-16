// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {UserConfiguration} from
    "@aave-v3-core/protocol/libraries/configuration/UserConfiguration.sol";
import {AaveV3Base} from "@src/hooks/aaveV3/AaveV3Base.sol";
import {Errors} from "@src/libs/Errors.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@src/libs/Constants.sol";

error AaveV3PositionManager_ATokenBalanceCheckFailed();

contract AaveV3PositionManager is AaveV3Base, IAfterTransaction {
    bytes4 constant ERC20_BALANCE_OF_SELECTOR = IERC20.balanceOf.selector;
    bytes4 constant DEPOSIT_FLAG = bytes4(keccak256("DEPOSIT"));
    bytes4 constant LEVERAGE_FLAG = bytes4(keccak256("LEVERAGE"));

    constructor(address _fund, address _aaveV3Pool) AaveV3Base(_fund, _aaveV3Pool) {}

    function createPositionPointer(address asset, bytes4 flag)
        private
        pure
        returns (bytes32 pointer)
    {
        pointer = keccak256(abi.encode(asset, flag, type(IPool).interfaceId));
    }

    function getATokenFundBalance(address asset) private view returns (uint256) {
        address aTokenAddress = aaveV3Pool.getReserveData(asset).aTokenAddress;
        (bool success, bytes memory data) = aTokenAddress.staticcall(
            abi.encodeWithSelector(ERC20_BALANCE_OF_SELECTOR, address(fund))
        );
        if (!success) {
            revert AaveV3PositionManager_ATokenBalanceCheckFailed();
        }
        return abi.decode(data, (uint256));
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

        address asset;
        assembly {
            asset := calldataload(data.offset)
        }

        if (selector == L1_WITHDRAW_SELECTOR || selector == L1_SUPPLY_SELECTOR) {
            uint256 balance = getATokenFundBalance(asset);

            /// if the balance is 0, then the position should be closed
            if (balance == 0) {
                /// @notice this is a no-op if the position is already closed
                fund.onPositionClosed(createPositionPointer(asset, DEPOSIT_FLAG));
            } else {
                fund.onPositionOpened(createPositionPointer(asset, DEPOSIT_FLAG));
            }
            /// check if user has been using any reserve for borrowing
            /// if there is debt => position is still open
            /// if there is no debt => position is closed
        } else if (
            selector == L1_BORROW_SELECTOR || selector == L1_REPAY_SELECTOR
                || selector == L1_REPAY_WITH_ATOKENS_SELECTOR
        ) {
            if (UserConfiguration.isBorrowingAny(aaveV3Pool.getUserConfiguration(address(fund)))) {
                fund.onPositionOpened(createPositionPointer(asset, LEVERAGE_FLAG));
            } else {
                /// @notice this is a no-op if the position is already closed
                fund.onPositionClosed(createPositionPointer(asset, LEVERAGE_FLAG));
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAfterTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
