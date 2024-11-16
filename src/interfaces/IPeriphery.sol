// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@src/interfaces/IFund.sol";
import "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/modules/deposit/Structs.sol";

interface IPeriphery {
    event Paused();

    event Unpaused();

    event AccountOpened(
        uint256 indexed accountId,
        Role role,
        uint256 expirationTimestamp,
        uint256 shareMintLimit,
        uint256 feeBps
    );

    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    event AssetEnabled(address asset, AssetPolicy policy);

    event AccountPaused(uint256 accountId);

    event AccountUnpaused(uint256 accountId);

    event AssetDisabled(address asset);

    event AdminUpdated(address oldAdmin, address newAdmin);

    event Deposit(
        uint256 indexed accountId,
        address asset,
        uint256 assetAmountIn,
        uint256 sharesOut,
        uint256 relayerFee
    );

    event Withdraw(
        uint256 indexed accountId,
        address asset,
        uint256 sharesIn,
        uint256 assetAmountOut,
        uint256 relayerFee
    );

    function fund() external returns (IFund);
    function oracleRouter() external returns (IPriceOracle);
    function paused() external returns (bool);
    function admin() external returns (address);
    function transferable() external returns (bool);
    function feeRecipient() external returns (address);
    function deposit(SignedDepositIntent calldata order) external returns (uint256 sharesOut);
    function withdraw(SignedWithdrawIntent calldata order)
        external
        returns (uint256 assetAmountOut);
    function peekNextTokenId() external returns (uint256);
    function setFeeRecipient(address newRecipient) external;
    function enableAsset(address asset, AssetPolicy memory policy) external;
    function disableAsset(address asset) external;
    function getAssetPolicy(address asset) external returns (AssetPolicy memory);
    function increaseAccountNonce(uint256 accountId, uint256 increment) external;
    function getAccountInfo(uint256 accountId) external returns (UserAccountInfo memory);
    function pauseAccount(uint256 accountId) external;
    function unpauseAccount(uint256 accountId) external;
    function openAccount(CreateAccountParams calldata params) external returns (uint256);
    function getAccountNonce(uint256 accountId) external returns (uint256);
    function fundIsOpen() external returns (bool);
}
