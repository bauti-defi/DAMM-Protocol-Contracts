// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@src/interfaces/IFund.sol";
import "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/modules/deposit/Structs.sol";
import {UnitOfAccount} from "@src/modules/deposit/UnitOfAccount.sol";
import {FundShareVault} from "@src/modules/deposit/FundShareVault.sol";
import {IPausable} from "@src/interfaces/IPausable.sol";

interface IPeriphery is IPausable {
    event AccountOpened(
        uint256 indexed accountId,
        Role role,
        uint256 expirationTimestamp,
        uint256 shareMintLimit,
        address feeRecipient,
        bool transferable
    );

    event ProtocolFeeRecipientUpdated(address oldRecipient, address newRecipient);

    event BrokerFeeRecipientUpdated(uint256 accountId, address oldRecipient, address newRecipient);

    event AssetEnabled(address asset, AssetPolicy policy);

    event AccountPaused(uint256 accountId);

    event AccountUnpaused(uint256 accountId);

    event AssetDisabled(address asset);

    event AdminUpdated(address oldAdmin, address newAdmin);

    event ManagementFeeRateUpdated(uint256 oldRateInBps, uint256 newRateInBps);

    event Deposit(
        uint256 indexed accountId,
        address asset,
        uint256 assetAmountIn,
        uint256 sharesOut,
        uint256 relayerFee,
        uint256 bribe,
        uint16 referralCode
    );

    event Withdraw(
        uint256 indexed accountId,
        address asset,
        uint256 sharesIn,
        uint256 netAssetAmountOut,
        uint256 relayerFee,
        uint256 bribe,
        uint16 referralCode
    );

    function fund() external returns (IFund);
    function oracleRouter() external returns (IPriceOracle);
    function admin() external returns (address);
    function internalVault() external returns (FundShareVault);
    function unitOfAccount() external returns (UnitOfAccount);
    function getVault() external returns (address);
    function getUnitOfAccountToken() external returns (address);
    function protocolFeeRecipient() external returns (address);
    function managementFeeRateInBps() external returns (uint256);
    function intentDeposit(SignedDepositIntent calldata order)
        external
        returns (uint256 sharesOut);
    function deposit(DepositOrder calldata order) external returns (uint256 sharesOut);
    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
        returns (uint256 assetAmountOut);
    function withdraw(WithdrawOrder calldata order) external returns (uint256 assetAmountOut);
    function peekNextTokenId() external returns (uint256);
    function setProtocolFeeRecipient(address newRecipient) external;
    function setManagementFeeRateInBps(uint256 rateInBps) external;
    function enableAsset(address asset, AssetPolicy memory policy) external;
    function disableAsset(address asset) external;
    function getAssetPolicy(address asset) external returns (AssetPolicy memory);
    function increaseAccountNonce(uint256 accountId, uint256 increment) external;
    function getAccountInfo(uint256 accountId) external returns (BrokerAccountInfo memory);
    function pauseAccount(uint256 accountId) external;
    function unpauseAccount(uint256 accountId) external;
    function openAccount(CreateAccountParams calldata params) external returns (uint256);
    function getAccountNonce(uint256 accountId) external returns (uint256);
    function fundIsOpen() external returns (bool);
}
