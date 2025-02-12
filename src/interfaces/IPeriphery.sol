// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

/// @title IPeriphery
/// @notice Interface for the Periphery contract which manages deposits, withdrawals, and brokerage accounts for a Fund
/// @dev Each Periphery is paired with exactly one Fund and manages its own ERC721 tokens representing brokerage accounts
import "@euler-price-oracle/interfaces/IPriceOracle.sol";
import "@src/modules/deposit/Structs.sol";
import {UnitOfAccount} from "@src/modules/deposit/UnitOfAccount.sol";
import {FundShareVault} from "@src/modules/deposit/FundShareVault.sol";

interface IPeriphery {
    event AccountOpened(
        uint256 indexed accountId,
        address user,
        uint256 expirationTimestamp,
        uint256 shareMintLimit,
        bool transferable,
        bool isPublic
    );

    event PeripherySetup(
        address indexed initiator, address indexed owner, address indexed avatar, address target
    );

    event ProtocolFeeRecipientUpdated(address oldRecipient, address newRecipient);

    event BrokerFeeRecipientUpdated(uint256 accountId, address oldRecipient, address newRecipient);

    event BrokerAssetPolicyEnabled(uint256 accountId, address asset, bool isDeposit);

    event BrokerAssetPolicyDisabled(uint256 accountId, address asset, bool isDeposit);

    event AccountPaused(uint256 accountId);

    event AccountUnpaused(uint256 accountId);

    event ManagementFeeRateUpdated(uint256 oldRateInBps, uint256 newRateInBps);

    event Deposit(
        uint256 indexed accountId,
        address indexed recipient,
        uint256 sharesOut,
        /// @dev denominated in shares
        uint256 netProtocolFee,
        /// @dev denominated in shares
        uint256 netBrokerFee
    );

    event Withdraw(
        uint256 indexed accountId,
        address indexed recipient,
        uint256 assetAmountOut,
        /// @dev denominated in asset
        uint256 netProtocolFee,
        /// @dev denominated in asset
        uint256 netBrokerFee
    );

    /// @notice The address that receives protocol fees
    function protocolFeeRecipient() external returns (address);

    /// @notice The annual management fee rate in basis points
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

    /// @notice Skims the management fee
    function skimManagementFee() external;

    /// @notice Enables an asset for deposits and withdrawals for a specific brokerage account
    /// @param accountId The ID of the brokerage account
    /// @param asset The asset to enable
    /// @param isDeposit Whether the asset is for deposits or withdrawals
    function enableBrokerAssetPolicy(uint256 accountId, address asset, bool isDeposit) external;

    /// @notice Disables an asset for deposits and withdrawals for a specific brokerage account
    /// @param accountId The ID of the brokerage account
    /// @param asset The asset to disable
    /// @param isDeposit Whether the asset is for deposits or withdrawals
    function disableBrokerAssetPolicy(uint256 accountId, address asset, bool isDeposit) external;

    /// @notice Checks if an asset is enabled for deposits or withdrawals for a specific brokerage account
    /// @param accountId The ID of the brokerage account
    /// @param asset The asset to check
    /// @param isDeposit Whether the asset is for deposits or withdrawals
    /// @return Whether the asset is enabled for deposits or withdrawals
    function isBrokerAssetPolicyEnabled(uint256 accountId, address asset, bool isDeposit)
        external
        returns (bool);

    /// @notice Updates the broker fee recipient for a specific brokerage account
    /// @param accountId The ID of the brokerage account
    /// @param recipient The new broker fee recipient
    function setBrokerFeeRecipient(uint256 accountId, address recipient) external;

    /// @notice Increases the nonce for a brokerage account
    /// @notice Increases the nonce for a brokerage account
    /// @param accountId The ID of the account to increase the nonce for
    /// @param increment The amount to increase the nonce by (minimum of 1)
    function increaseAccountNonce(uint256 accountId, uint256 increment) external;

    /// @notice The information for a brokerage account
    function getAccountInfo(uint256 accountId) external returns (BrokerAccountInfo memory);

    /// @notice Closes a brokerage account
    /// @param accountId The ID of the brokerage account to close
    function closeAccount(uint256 accountId) external;

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

    /// @notice Grants approval for the deposit module to manage the periphery's balance
    /// @notice Grants infinite approval
    /// @param token_ The address of the token to grant approval for
    function grantApproval(address token_) external;

    /// @notice Revokes approval for the deposit module to manage the periphery's balance
    /// @param token_ The address of the token to revoke approval for
    function revokeApproval(address token_) external;

    /// @notice Pauses the periphery
    function pause() external;

    /// @notice Unpauses the periphery
    function unpause() external;

    /// @notice Sets a new pauser
    /// @dev only the owner can set a pauser
    /// @param _pauser The address of the new pauser
    function setPauser(address _pauser) external;

    /// @notice Revokes a pauser
    /// @dev only the owner can revoke a pauser
    /// @param _pauser The address of the pauser to revoke
    function revokePauser(address _pauser) external;
}
