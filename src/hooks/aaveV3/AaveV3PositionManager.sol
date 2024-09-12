// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {IPortfolio} from "@src/interfaces/IPortfolio.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";
import {BaseHook} from "@src/hooks/BaseHook.sol";
import {Errors} from "@src/libs/Errors.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import "@src/libs/Constants.sol";

error AaveV3PositionManager_ATokenBalanceCheckFailed();

contract AaveV3PositionManager is BaseHook, IAfterTransaction {
    bytes4 constant L1_WITHDRAW_SELECTOR = IPool.withdraw.selector;
    bytes4 constant L1_SUPPLY_SELECTOR = IPool.supply.selector;
    bytes4 constant ERC20_BALANCE_OF_SELECTOR = IERC20.balanceOf.selector;

    IPool public immutable aaveV3Pool;

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

        if (selector == L1_WITHDRAW_SELECTOR || selector == L1_SUPPLY_SELECTOR) {
            address asset;
            assembly {
                asset := calldataload(data.offset)
            }

            uint256 balance = getATokenFundBalance(asset);

            /// if the balance is 0, then the position should be closed
            if (balance == 0) {
                /// @notice this is a no-op if the position is already closed
                fund.onPositionClosed(createPositionPointer(asset));
            } else {
                fund.onPositionOpened(createPositionPointer(asset));
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == type(IAfterTransaction).interfaceId
            || super.supportsInterface(interfaceId);
    }
}
