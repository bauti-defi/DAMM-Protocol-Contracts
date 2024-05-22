// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@src/deposits/DepositWithdrawStructs.sol";

interface IDepositWithdrawModule {
    event AssetEnabled(address asset);
    event AssetDisabled(address asset);
    event UserEnabled(address user, Role role);
    event UserDisabled(address user);
    event Deposit(
        address indexed user,
        address to,
        address asset,
        uint256 amount,
        uint256 valuation,
        uint256 tvl,
        address relayer
    );
    event Withdraw(
        address indexed user,
        address to,
        address asset,
        uint256 amount,
        uint256 valuation,
        uint256 tvl,
        address relayer
    );

    function getAssetPolicy(address asset) external view returns (AssetPolicy memory);

    function deposit(DepositOrder calldata order) external;

    function withdraw(WithdrawOrder calldata order) external;

    function enableAsset(address asset, AssetPolicy calldata policy) external;

    function disableAsset(address asset) external;
}
