// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@src/interfaces/IFund.sol";
import "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/modules/deposit/Structs.sol";

interface IPeriphery {
    event Paused();

    event Unpaused();

    event AccountOpened(uint256 indexed accountId, Role role, uint256 expirationTimestamp);

    event PerformanceFeeUpdated(uint256 oldFee, uint256 newFee);

    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    event AssetEnabled(address asset, AssetPolicy policy);

    event AssetDisabled(address asset);

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
    function deposit(SignedDepositIntent calldata order) external returns (uint256 sharesOut);
    function withdraw(SignedWithdrawIntent calldata order)
        external
        returns (uint256 assetAmountOut);
    function setFeeBps(uint256 newFeeBps) external;
    function getNextTokenId() external returns (uint256);
    function setFeeRecipient(address newRecipient) external;
    function enableAsset(address asset, AssetPolicy memory policy) external;
    function disableAsset(address asset) external;
    function getAssetPolicy(address asset) external returns (AssetPolicy memory);
    function increaseAccountNonce(uint256 accountId, uint256 increment) external;
    function getAccountInfo(uint256 accountId) external returns (UserAccountInfo memory);
    function pauseAccount(uint256 accountId) external;
    function unpauseAccount(uint256 accountId) external;
    // function openAccount(address user, Role role) external;
    function getAccountNonce(uint256 accountId) external returns (uint256);
}
