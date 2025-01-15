// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @title IPeriphery
/// @notice Interface for the Periphery contract which manages deposits, withdrawals, and brokerage accounts for a Fund
/// @dev Each Periphery is paired with exactly one Fund and manages its own ERC721 tokens representing brokerage accounts
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

    /// @notice The Fund contract this Periphery is associated with
    function fund() external returns (IFund);

    /// @notice The oracle used for price quotes
    function oracleRouter() external returns (IPriceOracle);

    /// @notice The admin address with minting privileges
    function admin() external returns (address);

    /// @notice The internal ERC4626 LP vault
    function internalVault() external returns (FundShareVault);

    /// @notice The token used for internal fund accounting
    function unitOfAccount() external returns (UnitOfAccount);

    /// @notice The address of the LP vault
    function getVault() external returns (address);

    /// @notice The address of the unit of account token
    function getUnitOfAccountToken() external returns (address);

    /// @notice The address that receives protocol fees
    function protocolFeeRecipient() external returns (address);

    /// @notice The management fee rate in basis points
    function managementFeeRateInBps() external returns (uint256);

    /// @notice Processes a signed deposit order
    /// @param order The signed deposit intent
    /// @return sharesOut Amount of vault shares minted
    function intentDeposit(SignedDepositIntent calldata order)
        external
        returns (uint256 sharesOut);

    /// @notice Processes a direct deposit order
    /// @param order The deposit order
    /// @return sharesOut Amount of vault shares minted
    function deposit(DepositOrder calldata order) external returns (uint256 sharesOut);

    /// @notice Processes a signed withdrawal order
    /// @param order The signed withdrawal intent
    /// @return assetAmountOut Amount of asset tokens withdrawn
    function intentWithdraw(SignedWithdrawIntent calldata order)
        external
        returns (uint256 assetAmountOut);

    /// @notice Processes a direct withdrawal order
    /// @param order The withdrawal order
    /// @return assetAmountOut Amount of asset tokens withdrawn
    function withdraw(WithdrawOrder calldata order) external returns (uint256 assetAmountOut);

    /// @notice The next token ID that will be used for a new brokerage account
    function peekNextTokenId() external returns (uint256);

    /// @notice Updates the protocol fee recipient address
    function setProtocolFeeRecipient(address newRecipient) external;

    /// @notice Updates the management fee rate
    function setManagementFeeRateInBps(uint256 rateInBps) external;

    /// @notice Enables an asset for deposits and withdrawals
    /// @param asset The asset to enable
    /// @param policy The deposit/withdrawal policy for the asset
    function enableAsset(address asset, AssetPolicy memory policy) external;

    /// @notice Disables an asset for deposits and withdrawals
    /// @param asset The asset to disable
    function disableAsset(address asset) external;

    /// @notice Gets the deposit/withdrawal policy for an asset
    /// @param asset The asset to get the policy for
    /// @return The asset's policy
    function getAssetPolicy(address asset) external returns (AssetPolicy memory);

    /// @notice Increases the nonce for a brokerage account
    /// @param accountId The ID of the account to increase the nonce for
    /// @param increment The amount to increase the nonce by (minimum of 1)
    function increaseAccountNonce(uint256 accountId, uint256 increment) external;

    /// @notice The information for a brokerage account
    function getAccountInfo(uint256 accountId) external returns (BrokerAccountInfo memory);

    /// @notice Pauses a brokerage account
    function pauseAccount(uint256 accountId) external;

    /// @notice Unpauses a brokerage account
    function unpauseAccount(uint256 accountId) external;

    /// @notice Creates a new brokerage account
    /// @param params The parameters for the new account
    /// @return The ID of the new account
    function openAccount(CreateAccountParams calldata params) external returns (uint256);

    /// @notice The current nonce for a brokerage account
    function getAccountNonce(uint256 accountId) external returns (uint256);

    /// @notice Whether the fund has any open positions
    function fundIsOpen() external returns (bool);
}
