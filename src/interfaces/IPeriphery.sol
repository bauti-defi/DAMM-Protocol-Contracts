// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@src/modules/deposit/Structs.sol";

interface IPeriphery {
    function totalAssets() external view returns (uint256);
    function deposit(DepositOrder calldata order) external returns (uint256 sharesOut);
    function withdraw(WithdrawOrder calldata order) external returns (uint256 assetAmountOut);
    function withdrawFees(address asset, uint256 shares, uint256 minAmountOut)
        external
        returns (uint256 assetAmountOut);
    function setFeeRecipient(address newFeeRecipient) external;
    function setFeeBps(uint256 newFeeBps) external;
    function enableAsset(address asset, AssetPolicy memory policy) external;
    function disableAsset(address asset) external;
    function getAssetPolicy(address asset) external returns (AssetPolicy memory);
    function increaseNonce(uint256 increment) external;
    function getUserAccountInfo(address user) external returns (UserAccountInfo memory);
    function pauseAccount(address user) external;
    function unpauseAccount(address user) external;
    function updateAccountRole(address user, Role role) external;
    function openAccount(address user, Role role) external;
}
