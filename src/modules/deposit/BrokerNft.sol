// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@openzeppelin-contracts/utils/math/SignedMath.sol";
import "@openzeppelin-contracts/utils/math/SafeCast.sol";
import "@solady/utils/FixedPointMathLib.sol";
import "@src/libs/Constants.sol";

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import "@src/libs/Errors.sol";
import "@zodiac/interfaces/IAvatar.sol";
import "@src/interfaces/IBrokerNft.sol";
import "./UnitOfAccount.sol";
import {FundShareVault} from "./FundShareVault.sol";
import {DepositLibs} from "./DepositLibs.sol";
import {SafeLib} from "@src/libs/SafeLib.sol";
import {IPermit2} from "@permit2/src/interfaces/IPermit2.sol";
import "@zodiac/factory/FactoryFriendly.sol";
import "@src/interfaces/IBrokerNft.sol";
import "@src/interfaces/IBrokerNft.sol";
bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
bytes32 constant CONTROLLER_ROLE = keccak256("CONTROLLER_ROLE");
bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

/// @title Periphery
/// @notice Manages deposits, withdrawals, and brokerage accounts for a Fund
/// @dev Each Periphery is paired with exactly one Fund and manages ERC721 tokens representing brokerage accounts.
///      The Periphery handles:
///      - Asset deposits/withdrawals through the DepositModule
///      - Broker account management (NFTs)
///      - Fee collection and distribution
contract BrokerNft is
    FactoryFriendly,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IBrokerNft
{
    using DepositLibs for BrokerAccountInfo;
    using DepositLibs for address;
    using DepositLibs for ERC20;
    using SafeTransferLib for ERC20;
    using SafeLib for IAvatar;
    using SafeCast for uint256;
    using SignedMath for int256;
    using FixedPointMathLib for uint256;

    /// @dev Maps token IDs to their brokerage account information
    mapping(uint256 tokenId => Broker broker) private brokers;

    /// @dev Counter for brokerage account token IDs
    uint256 private tokenId = 0;

    /// @notice Initializes the Periphery contract
    /// @param initializeParams Encoded parameters for the Periphery contract
    function setUp(bytes memory initializeParams) public override initializer {
        /// @dev vaultName_ Name of the Brokerage NFT
        /// @dev vaultSymbol_ Symbol of the Brokerage NFT
        /// @dev owner_ Address that owns the Periphery
        /// @dev minter_ Address with minting privileges
        /// @dev depositModule_ Address of the deposit module
        /// @dev protocolFeeRecipient_ Address that receives protocol fees
        (
            string memory brokerNftName_,
            string memory brokerNftSymbol_,
            address owner_,
            address minter_,
            address controller_
        ) = abi.decode(
            initializeParams, (string, string, address, address, address)
        );
        if (owner_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (minter_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }

        _transferOwnership(owner_);
        __Pausable_init();
        __ReentrancyGuard_init();
        __AccessControl_init();
        __ERC721_init(brokerNftName_, brokerNftSymbol_);

        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        _grantRole(PAUSER_ROLE, owner_);
        _grantRole(MINTER_ROLE, minter_);
        _grantRole(CONTROLLER_ROLE, controller_);
    }

    /// @dev this modifier ensures that the account info is zeroed out if the broker has no shares outstanding
    modifier zeroOutAccountInfo(uint256 accountId_) {
        _;
        if (brokers[accountId_].account.totalSharesOutstanding == 0) {
            brokers[accountId_].account.cumulativeSharesMinted = 0;
            brokers[accountId_].account.cumulativeUnitsDeposited = 0;
        }
    }

    function _getBrokerOrRevert(uint256 accountId_)
        private
        view
        returns (Broker storage broker, address brokerAddress)
    {
        brokerAddress = _ownerOf(accountId_);
        if (brokerAddress == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }

        broker = brokers[accountId_];
    }

    function _validateBrokerAssetPolicy(address asset, Broker storage broker, bool isDeposit)
        internal
        view
    {
        BrokerAccountInfo memory account = broker.account;
        if (!account.isActive()) revert Errors.Deposit_AccountNotActive();

        if (account.isExpired() && isDeposit) {
            revert Errors.Deposit_AccountExpired();
        }

        if (!broker.assetPolicy[asset.brokerAssetPolicyPointer(isDeposit)]) {
            revert Errors.Deposit_AssetUnavailable();
        }
    }

    /// @inheritdoc IBrokerNft
    function getAccountNonce(uint256 accountId_) external view returns (uint256) {
        return brokers[accountId_].account.nonce;
    }

    /// @inheritdoc IBrokerNft
    function setBrokerFeeRecipient(uint256 accountId_, address recipient_) external {
        address broker = _ownerOf(accountId_);
        if (broker == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }
        if (broker != msg.sender) {
            revert Errors.Deposit_OnlyAccountOwner();
        }
        if (recipient_ == address(0)) {
            revert Errors.Deposit_InvalidBrokerFeeRecipient();
        }

        address previous = brokers[accountId_].account.feeRecipient;

        brokers[accountId_].account.feeRecipient = recipient_;

        emit BrokerFeeRecipientUpdated(accountId_, recipient_, previous);
    }

    /// @inheritdoc IBrokerNft
    function enableBrokerAssetPolicy(uint256 accountId_, address asset_, bool isDeposit_)
        external
        whenNotPaused
        onlyRole(CONTROLLER_ROLE)
    {
        Broker storage broker = brokers[accountId_];

        if (!broker.account.isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }
        if (broker.account.isExpired()) {
            revert Errors.Deposit_AccountExpired();
        }

        broker.assetPolicy[asset_.brokerAssetPolicyPointer(isDeposit_)] = true;

        emit BrokerAssetPolicyEnabled(accountId_, asset_, isDeposit_);
    }

    /// @inheritdoc IBrokerNft
    function disableBrokerAssetPolicy(uint256 accountId_, address asset_, bool isDeposit_)
        external
        onlyRole(CONTROLLER_ROLE)
    {
        Broker storage broker = brokers[accountId_];

        if (!broker.account.isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }
        if (broker.account.isExpired()) {
            revert Errors.Deposit_AccountExpired();
        }

        broker.assetPolicy[asset_.brokerAssetPolicyPointer(isDeposit_)] = false;

        emit BrokerAssetPolicyDisabled(accountId_, asset_, isDeposit_);
    }

    /// @inheritdoc IBrokerNft
    function isBrokerAssetPolicyEnabled(uint256 accountId_, address asset_, bool isDeposit_)
        external
        view
        returns (bool)
    {
        return brokers[accountId_].assetPolicy[asset_.brokerAssetPolicyPointer(isDeposit_)];
    }

    /// @notice restricting the transfer makes this a soulbound token
    function transferFrom(address from_, address to_, uint256 tokenId_) public override {
        if (!brokers[tokenId_].account.transferable) revert Errors.Deposit_AccountNotTransferable();

        super.transferFrom(from_, to_, tokenId_);
    }

    /// @inheritdoc IBrokerNft
    function openAccount(CreateAccountParams calldata params_)
        public
        whenNotPaused
        nonReentrant
        onlyRole(MINTER_ROLE)
        returns (uint256 nextTokenId)
    {
        if (params_.user == address(0)) {
            revert Errors.Deposit_InvalidUser();
        }
        if (params_.brokerPerformanceFeeInBps + params_.protocolPerformanceFeeInBps >= BP_DIVISOR) {
            revert Errors.Deposit_InvalidPerformanceFee();
        }
        if (params_.brokerEntranceFeeInBps + params_.protocolEntranceFeeInBps >= BP_DIVISOR) {
            revert Errors.Deposit_InvalidEntranceFee();
        }
        if (params_.brokerExitFeeInBps + params_.protocolExitFeeInBps >= BP_DIVISOR) {
            revert Errors.Deposit_InvalidExitFee();
        }
        if (params_.ttl == 0) {
            revert Errors.Deposit_InvalidTTL();
        }
        if (params_.shareMintLimit == 0) {
            revert Errors.Deposit_InvalidShareMintLimit();
        }

        address feeRecipient =
            params_.feeRecipient == address(0) ? params_.user : params_.feeRecipient;

        unchecked {
            nextTokenId = ++tokenId;
        }

        /// @notice If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
        _safeMint(params_.user, nextTokenId);

        brokers[nextTokenId].account = BrokerAccountInfo({
            transferable: params_.transferable,
            state: AccountState.ACTIVE,
            expirationTimestamp: block.timestamp + params_.ttl,
            nonce: 0,
            feeRecipient: feeRecipient,
            shareMintLimit: params_.shareMintLimit,
            cumulativeSharesMinted: 0,
            cumulativeUnitsDeposited: 0,
            totalSharesOutstanding: 0,
            brokerPerformanceFeeInBps: params_.brokerPerformanceFeeInBps,
            protocolPerformanceFeeInBps: params_.protocolPerformanceFeeInBps,
            brokerEntranceFeeInBps: params_.brokerEntranceFeeInBps,
            protocolEntranceFeeInBps: params_.protocolEntranceFeeInBps,
            brokerExitFeeInBps: params_.brokerExitFeeInBps,
            protocolExitFeeInBps: params_.protocolExitFeeInBps
        });

        emit AccountOpened(
            nextTokenId,
            block.timestamp + params_.ttl,
            params_.shareMintLimit,
            feeRecipient,
            params_.transferable
        );
    }

    /// @inheritdoc IBrokerNft
    function closeAccount(uint256 accountId_) public onlyRole(MINTER_ROLE) {
        if (!brokers[accountId_].account.canBeClosed()) {
            revert Errors.Deposit_AccountCannotBeClosed();
        }
        /// @notice this will revert if the token does not exist
        _burn(accountId_);
        brokers[accountId_].account.state = AccountState.CLOSED;
    }

    /// @inheritdoc IBrokerNft
    function pauseAccount(uint256 accountId_) public onlyRole(MINTER_ROLE) {
        if (!brokers[accountId_].account.isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }
        if (_ownerOf(accountId_) == address(0)) revert Errors.Deposit_AccountDoesNotExist();
        brokers[accountId_].account.state = AccountState.PAUSED;

        emit AccountPaused(accountId_);
    }

    /// @inheritdoc IBrokerNft
    function unpauseAccount(uint256 accountId_) public whenNotPaused onlyRole(MINTER_ROLE) {
        if (!brokers[accountId_].account.isPaused()) {
            revert Errors.Deposit_AccountNotPaused();
        }
        if (_ownerOf(accountId_) == address(0)) revert Errors.Deposit_AccountDoesNotExist();
        brokers[accountId_].account.state = AccountState.ACTIVE;

        /// increase nonce to avoid replay attacks
        brokers[accountId_].account.nonce++;

        emit AccountUnpaused(accountId_);
    }

    /// @inheritdoc IBrokerNft
    function getAccountInfo(uint256 accountId_) public view returns (BrokerAccountInfo memory) {
        return brokers[accountId_].account;
    }

    /// @inheritdoc IBrokerNft
    function increaseAccountNonce(uint256 accountId_, uint256 increment_) external whenNotPaused {
        if (_ownerOf(accountId_) != msg.sender) revert Errors.Deposit_OnlyAccountOwner();
        if (brokers[accountId_].account.isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }

        brokers[accountId_].account.nonce += increment_ > 1 ? increment_ : 1;
    }

    /// @inheritdoc IBrokerNft
    function peekNextTokenId() public view returns (uint256) {
        return tokenId + 1;
    }

    /// @inheritdoc IBrokerNft
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc IBrokerNft
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @inheritdoc IBrokerNft
    function setPauser(address _pauser) external onlyRole(CONTROLLER_ROLE) {
        _grantRole(PAUSER_ROLE, _pauser);
    }

    /// @inheritdoc IBrokerNft
    function revokePauser(address _pauser) external onlyRole(CONTROLLER_ROLE) {
        _revokeRole(PAUSER_ROLE, _pauser);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return interfaceId == type(IBrokerNft).interfaceId || super.supportsInterface(interfaceId);
    }
}
