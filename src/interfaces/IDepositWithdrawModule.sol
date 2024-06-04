// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@src/deposits/DepositWithdrawStructs.sol";

interface IDepositWithdrawModule {
    event AssetEnabled(address asset);
    event AssetDisabled(address asset);
    event AccountOpened(address indexed user, uint256 epoch, Role role);
    event AccountRoleChanged(address indexed user, Role role);
    event AccountPaused(address indexed user);
    event AccountUnpaused(address indexed user);
    event Deposit(
        address indexed user, address asset, uint256 amount, uint256 shares, address relayer
    );
    event Withdraw(
        address indexed user,
        address to,
        address asset,
        uint256 amount,
        uint256 withdrawValuation,
        uint256 sharesBurnt,
        address relayer
    );

    event EpochStarted(uint256 indexed epoch);

    event FeeWithdraw(address recipient, address asset, uint256 amount, uint256 shares);

    event EpochFeeCollected(address indexed user, uint256 fee, uint256 shares, address receiver);

    function getAssetPolicy(address asset) external view returns (AssetPolicy memory);

    function deposit(DepositOrder calldata order) external;

    function withdraw(WithdrawOrder calldata order) external;

    function enableAsset(address asset, AssetPolicy calldata policy) external;

    function disableAsset(address asset) external;
}
