// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IBeforeTransaction, IAfterTransaction} from "@src/interfaces/ITransactionHooks.sol";
import {IFund} from "@src/interfaces/IFund.sol";
import {IPool} from "@aave-v3-core/interfaces/IPool.sol";

contract AaveV3Hooks is IBeforeTransaction, IAfterTransaction {
    error OnlyFund();
    error OnlyWhitelistedTokens();

    bytes32 constant POSITION_POINTER = keccak256("aave.v3.hooks");

    bytes4 constant L1_WITHDRAW_SELECTOR = 0x69328dec;
    bytes4 constant L1_SUPPLY_SELECTOR = 0x617ba037;

    IFund public immutable fund;
    IPool public immutable aaveV3Pool;

    mapping(address asset => bool whitelisted) public assetWhitelist;

    constructor(address _fund, address _aaveV3Pool) {
        fund = IFund(_fund);
        aaveV3Pool = IPool(_aaveV3Pool);
    }

    modifier onlyFund() {
        if (msg.sender != address(fund)) {
            revert OnlyFund();
        }
        _;
    }

    function checkBeforeTransaction(
        address target,
        bytes4 selector,
        uint8,
        uint256,
        bytes calldata data
    ) external view override onlyFund {
        require(target == address(aaveV3Pool), "target not aave pool");

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
            revert("unsupported selector");
        }

        if (!assetWhitelist[asset]) {
            revert OnlyWhitelistedTokens();
        }
        if (onBehalfOf != address(fund)) {
            revert OnlyFund();
        }
    }

    function checkAfterTransaction(
        address target,
        bytes4 selector,
        uint8,
        uint256,
        bytes calldata,
        bytes calldata
    ) external override onlyFund {
        require(target == address(aaveV3Pool), "pool not aave pool");

        if (selector == L1_SUPPLY_SELECTOR) {
            /// @dev open position if not already open
            /// that means all open aave positions are represented by a single pointer
            if (!fund.holdsPosition(POSITION_POINTER)) {
                require(fund.onPositionOpened(POSITION_POINTER), "failed to open position");
            }
        } else if (selector == L1_WITHDRAW_SELECTOR) {
            (uint256 collateralDeposited,,,,,) = aaveV3Pool.getUserAccountData(address(fund));
            if (collateralDeposited == 0) {
                require(fund.onPositionClosed(POSITION_POINTER), "failed to close position");
            }
        }
    }

    function enableAsset(address asset) external onlyFund {
        require(asset != address(0), "invalid asset address");
        require(asset != address(fund), "cannot enable fund");
        require(asset != address(this), "cannot enable self");
        require(asset != address(aaveV3Pool), "cannot enable pool");

        assetWhitelist[asset] = true;
    }

    function disableAsset(address asset) external onlyFund {
        assetWhitelist[asset] = false;
    }
}
