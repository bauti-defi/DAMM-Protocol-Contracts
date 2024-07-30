// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@src/interfaces/IFund.sol";
import "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/modules/deposit/Structs.sol";

interface IPeriphery {
    event Paused();

    event Unpaused();

    event AssetEnabled(address asset, AssetPolicy policy);

    event AssetDisabled(address asset);

    event AccountOpened(address indexed user, Role role);

    event AccountRoleChanged(address indexed user, Role oldRole, Role newRole);

    event AccountPaused(address indexed user);

    event AccountUnpaused(address indexed user);

    event FeeRecipientUpdated(address newRecipient, address oldRecipient);

    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);

    event Deposit(
        address indexed user,
        address asset,
        uint256 assetAmountIn,
        uint256 sharesOut,
        address relayer,
        uint256 relayerTip
    );

    event Withdraw(
        address indexed user,
        address to,
        address asset,
        uint256 sharesIn,
        uint256 assetAmountOut,
        address relayer,
        uint256 relayerTip
    );

    event WithdrawFees(address indexed to, address asset, uint256 sharesIn, uint256 assetAmountOut);

    function fund() external returns (IFund);
    function oracleRouter() external returns (IPriceOracle);
    function paused() external returns (bool);
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
