// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@openzeppelin-contracts/token/ERC721/ERC721.sol";
import "@openzeppelin-contracts/utils/math/SignedMath.sol";
import "@openzeppelin-contracts/utils/math/SafeCast.sol";
import "@openzeppelin-contracts/access/AccessControl.sol";
import "@openzeppelin-contracts/utils/Pausable.sol";
import "@solady/utils/FixedPointMathLib.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@solady/utils/ReentrancyGuard.sol";
import "@src/libs/Constants.sol";

import "@src/libs/Errors.sol";
import "@src/interfaces/ISafe.sol";
import "@src/interfaces/IPeriphery.sol";
import "./UnitOfAccount.sol";
import {FundShareVault} from "./FundShareVault.sol";
import {DepositLibs} from "./DepositLibs.sol";
import {SafeLib} from "@src/libs/SafeLib.sol";

bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
bytes32 constant FUND_ROLE = keccak256("FUND_ROLE");
bytes32 constant MINTER_ROLE = keccak256("MINTER_ROLE");

/// @title Periphery
/// @notice Manages deposits, withdrawals, and brokerage accounts for a Fund
/// @dev Each Periphery is paired with exactly one Fund and manages ERC721 tokens representing brokerage accounts.
///      The Periphery handles:
///      - Asset deposits/withdrawals through the Fund
///      - Unit of account token minting/burning
///      - ERC4626 vault share accounting
///      - Broker account management (NFTs)
///      - Fee collection and distribution
contract Periphery is ERC721, AccessControl, Pausable, ReentrancyGuard, IPeriphery {
    using DepositLibs for BrokerAccountInfo;
    using DepositLibs for address;
    using SafeLib for ISafe;
    using SafeTransferLib for ERC20;
    using SafeCast for uint256;
    using SignedMath for int256;
    using FixedPointMathLib for uint256;

    /// @dev The DAMM fund the periphery is associated with
    address public immutable fund;
    /// @dev The oracle used for price quotes
    IPriceOracle public immutable oracleRouter;
    /// @dev Common unit of account for assets and internalVault
    UnitOfAccount public immutable unitOfAccount;
    /// @dev Used internally for yield accounting
    FundShareVault public immutable internalVault;

    /// @dev The recipient of the protocol fees
    address public protocolFeeRecipient;
    /// @dev Timestamp of the last management fee collection
    uint256 private lastManagementFeeTimestamp;
    /// @dev The management fee rate in basis points
    uint256 public managementFeeRateInBps;

    /// @dev The maximum amount of assets that can be deposited into the fund
    /// @notice fund valuation must be less than or equal to this value to accept deposits
    /// @notice default is set to type(uint256).max
    uint256 public netDepositLimit;

    /// @dev Maps assets to their deposit/withdrawal policies
    mapping(address asset => AssetPolicy policy) private assetPolicy;

    /// @dev Maps token IDs to their brokerage account information
    mapping(uint256 tokenId => Broker broker) private brokers;

    /// @dev Counter for brokerage account token IDs
    uint256 private tokenId = 0;

    /// @notice Initializes the Periphery contract
    /// @param vaultName_ Name of the ERC4626 vault
    /// @param vaultSymbol_ Symbol of the ERC4626 vault
    /// @param decimals_ Decimals for the unit of account token
    /// @param fund_ Address of the Fund contract
    /// @param oracleRouter_ Address of the oracle router for quotes
    /// @param minter_ Address with minting privileges
    /// @param protocolFeeRecipient_ Address that receives protocol fees
    constructor(
        string memory vaultName_,
        string memory vaultSymbol_,
        uint8 decimals_,
        address fund_,
        address oracleRouter_,
        address minter_,
        address protocolFeeRecipient_
    ) ERC721(vaultName_, vaultSymbol_) {
        if (fund_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (oracleRouter_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (minter_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (protocolFeeRecipient_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }

        fund = fund_;
        oracleRouter = IPriceOracle(oracleRouter_);
        protocolFeeRecipient = protocolFeeRecipient_;
        lastManagementFeeTimestamp = block.timestamp;
        netDepositLimit = type(uint256).max;
        unitOfAccount = new UnitOfAccount("Liquidity", "UNIT", decimals_);
        internalVault = new FundShareVault(address(unitOfAccount), vaultName_, vaultSymbol_);

        _grantRole(DEFAULT_ADMIN_ROLE, fund_);
        _grantRole(FUND_ROLE, fund_);
        _grantRole(PAUSER_ROLE, fund_);
        _grantRole(MINTER_ROLE, minter_);
        _grantRole(MINTER_ROLE, fund_);

        /// @notice infinite approval for the internalVault to manage periphery's balance
        unitOfAccount.approve(address(internalVault), type(uint256).max);
    }

    /// @dev This modifier updates the balances of the internalVault and the fund
    /// this ensures that the internalVault's total assets are always equal to the fund's total assets
    modifier rebalanceVault() {
        _updateVaultBalance();

        _;

        _updateVaultBalance();
    }

    /// @dev this modifier ensures that the account info is zeroed out if the broker has no shares outstanding
    modifier zeroOutAccountInfo(uint256 accountId_) {
        _;
        if (brokers[accountId_].account.totalSharesOutstanding == 0) {
            brokers[accountId_].account.cumulativeSharesMinted = 0;
            brokers[accountId_].account.cumulativeUnitsDeposited = 0;
        }
    }

    /// @inheritdoc IPeriphery
    function intentDeposit(SignedDepositIntent calldata order)
        public
        whenNotPaused
        nonReentrant
        rebalanceVault
        returns (uint256 sharesOut)
    {
        address minter = _ownerOf(order.intent.deposit.accountId);
        if (minter == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }

        AssetPolicy memory policy = assetPolicy[order.intent.deposit.asset];
        Broker storage broker = brokers[order.intent.deposit.accountId];

        DepositLibs.validateBrokerAssetPolicy(order.intent.deposit.asset, broker, policy, true);

        DepositLibs.validateIntent(
            abi.encode(order.intent),
            order.signature,
            minter,
            order.intent.chaindId,
            broker.account.nonce++,
            order.intent.nonce
        );

        /// @notice The management fee should be charged before the deposit is processed
        /// otherwise, the management fee will be charged on the deposit amount
        _takeManagementFee();

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            ERC20(order.intent.deposit.asset).safeTransferFrom(
                minter, msg.sender, order.intent.relayerTip
            );
        }

        /// bribe the fund if required
        if (order.intent.bribe > 0) {
            ERC20(order.intent.deposit.asset).safeTransferFrom(minter, fund, order.intent.bribe);
        }

        sharesOut = _deposit(
            order.intent.deposit,
            minter,
            policy.minimumDeposit,
            broker.account.totalSharesOutstanding,
            broker.account.shareMintLimit,
            broker.account.brokerEntranceFeeInBps,
            broker.account.protocolEntranceFeeInBps
        );

        emit Deposit(
            order.intent.deposit.accountId,
            order.intent.deposit.asset,
            order.intent.deposit.amount,
            sharesOut,
            order.intent.relayerTip,
            order.intent.bribe,
            order.intent.deposit.referralCode
        );
    }

    /// @inheritdoc IPeriphery
    function deposit(DepositOrder calldata order)
        public
        whenNotPaused
        nonReentrant
        rebalanceVault
        returns (uint256 sharesOut)
    {
        address minter = _ownerOf(order.accountId);
        if (minter == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }

        if (minter != msg.sender) {
            revert Errors.Deposit_OnlyAccountOwner();
        }

        /// @notice The management fee should be charged before the deposit is processed
        /// otherwise, the management fee will be charged on the deposit amount
        _takeManagementFee();

        AssetPolicy memory policy = assetPolicy[order.asset];
        Broker storage broker = brokers[order.accountId];

        DepositLibs.validateBrokerAssetPolicy(order.asset, broker, policy, true);

        sharesOut = _deposit(
            order,
            minter,
            policy.minimumDeposit,
            broker.account.totalSharesOutstanding,
            broker.account.shareMintLimit,
            broker.account.brokerEntranceFeeInBps,
            broker.account.protocolEntranceFeeInBps
        );

        emit Deposit(
            order.accountId, order.asset, order.amount, sharesOut, 0, 0, order.referralCode
        );
    }

    function _deposit(
        DepositOrder calldata order,
        address broker,
        uint256 minimumDeposit,
        uint256 totalSharesOutstanding,
        uint256 shareMintLimit,
        uint256 brokerEntranceFeeInBps,
        uint256 protocolEntranceFeeInBps
    ) private returns (uint256 sharesOut) {
        if (order.deadline < block.timestamp) {
            revert Errors.Deposit_OrderExpired();
        }

        uint256 assetAmountIn = order.amount;
        ERC20 assetToken = ERC20(order.asset);

        if (assetAmountIn == 0) {
            revert Errors.Deposit_InsufficientDeposit();
        }

        /// if amount is type(uint256).max, then deposit the broker's entire balance
        if (assetAmountIn == type(uint256).max) {
            assetAmountIn = assetToken.balanceOf(broker);
        }

        /// make sure the deposit is above the minimum
        if (assetAmountIn < minimumDeposit) {
            revert Errors.Deposit_InsufficientDeposit();
        }

        /// transfer asset from broker to fund
        assetToken.safeTransferFrom(broker, fund, assetAmountIn);

        /// calculate how much liquidity for this amount of deposited asset
        uint256 liquidity =
            oracleRouter.getQuote(assetAmountIn, order.asset, address(unitOfAccount));

        /// mint liquidity to periphery
        unitOfAccount.mint(address(this), liquidity);

        /// mint shares to the periphery using the liquidity that was just minted
        sharesOut = internalVault.deposit(liquidity, address(this));

        /// check if the net deposit limit is exceeded
        if (internalVault.totalAssets() > netDepositLimit) {
            revert Errors.Deposit_NetDepositLimitExceeded();
        }

        /// @notice this edge case is possible if a big amount of token is transferred
        /// to the fund before the deposit is processed
        if (sharesOut == 0) {
            revert Errors.Deposit_InsufficientShares();
        }

        /// lets make sure slippage is acceptable
        if (sharesOut < order.minSharesOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
        }

        /// make sure the broker hasn't exceeded their share mint limit
        if (totalSharesOutstanding + sharesOut > shareMintLimit) {
            revert Errors.Deposit_ShareMintLimitExceeded();
        }

        /// update the broker's cumulative units deposited
        brokers[order.accountId].account.cumulativeUnitsDeposited += liquidity;

        /// update the broker's total shares outstanding
        brokers[order.accountId].account.totalSharesOutstanding += sharesOut;

        /// update the broker's cumulative shares minted
        brokers[order.accountId].account.cumulativeSharesMinted += sharesOut;

        /// take the broker entrance fees
        if (brokerEntranceFeeInBps > 0) {
            internalVault.transfer(
                broker, sharesOut.fullMulDivUp(brokerEntranceFeeInBps, BP_DIVISOR)
            );
        }

        /// take the protocol entrance fees
        if (protocolEntranceFeeInBps > 0) {
            internalVault.transfer(
                protocolFeeRecipient, sharesOut.fullMulDivUp(protocolEntranceFeeInBps, BP_DIVISOR)
            );
        }

        /// forward the remaining shares to the recipient
        internalVault.transfer(order.recipient, internalVault.balanceOf(address(this)));
    }

    function intentWithdraw(SignedWithdrawIntent calldata order)
        public
        whenNotPaused
        nonReentrant
        rebalanceVault
        zeroOutAccountInfo(order.intent.withdraw.accountId)
        returns (uint256 assetAmountOut)
    {
        address burner = _ownerOf(order.intent.withdraw.accountId);
        if (burner == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }

        AssetPolicy memory policy = assetPolicy[order.intent.withdraw.asset];
        Broker storage broker = brokers[order.intent.withdraw.accountId];

        DepositLibs.validateBrokerAssetPolicy(order.intent.withdraw.asset, broker, policy, false);

        DepositLibs.validateIntent(
            abi.encode(order.intent),
            order.signature,
            burner,
            order.intent.chaindId,
            broker.account.nonce++,
            order.intent.nonce
        );

        /// @notice The management fee should be charged before the withdrawal is processed
        /// otherwise, the management fee will be charged on the withdrawal amount
        _takeManagementFee();

        (uint256 netAssetAmountOut, uint256 netBrokerFee, uint256 netProtocolFee) =
            _withdraw(burner, order.intent.withdraw, broker.account, policy.minimumWithdrawal);

        /// start calculating the amount of asset to transfer to the user
        assetAmountOut = netAssetAmountOut - netBrokerFee - netProtocolFee;

        /// check that we can pay the bribe and relay tip with the net asset amount out
        if (assetAmountOut < order.intent.bribe + order.intent.relayerTip) {
            revert Errors.Deposit_InsufficientAmount();
        }

        /// deduct the bribe and relay tip from the net asset amount out
        /// @notice this will implicitly pay the bribe to the fund
        assetAmountOut = assetAmountOut - order.intent.relayerTip - order.intent.bribe;

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            ISafe(fund).transferAssetFromSafeOrRevert(
                order.intent.withdraw.asset, msg.sender, order.intent.relayerTip
            );
        }

        /// distribute the funds to the user, broker, and protocol
        _distributeFunds(
            order.intent.withdraw.asset,
            order.intent.withdraw.to,
            burner,
            assetAmountOut,
            netBrokerFee,
            netProtocolFee
        );

        emit Withdraw(
            order.intent.withdraw.accountId,
            order.intent.withdraw.asset,
            order.intent.withdraw.shares,
            netAssetAmountOut,
            order.intent.relayerTip,
            order.intent.bribe,
            order.intent.withdraw.referralCode
        );
    }

    function withdraw(WithdrawOrder calldata order)
        public
        whenNotPaused
        nonReentrant
        rebalanceVault
        zeroOutAccountInfo(order.accountId)
        returns (uint256 assetAmountOut)
    {
        address burner = _ownerOf(order.accountId);
        if (burner == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }

        if (burner != msg.sender) {
            revert Errors.Deposit_OnlyAccountOwner();
        }

        AssetPolicy memory policy = assetPolicy[order.asset];
        Broker storage broker = brokers[order.accountId];

        DepositLibs.validateBrokerAssetPolicy(order.asset, broker, policy, false);

        /// @notice The management fee should be charged before the withdrawal is processed
        /// otherwise, the management fee will be charged on the withdrawal amount
        _takeManagementFee();

        (uint256 netAssetAmountOut, uint256 netBrokerFee, uint256 netProtocolFee) =
            _withdraw(burner, order, broker.account, policy.minimumWithdrawal);

        assetAmountOut = netAssetAmountOut - netBrokerFee - netProtocolFee;

        /// distribute the funds to the user, broker, and protocol
        _distributeFunds(
            order.asset, order.to, burner, assetAmountOut, netBrokerFee, netProtocolFee
        );

        emit Withdraw(
            order.accountId, order.asset, order.shares, netAssetAmountOut, 0, 0, order.referralCode
        );
    }

    function _withdraw(
        address broker,
        WithdrawOrder calldata order,
        BrokerAccountInfo memory account,
        uint256 minimumWithdrawal
    ) private returns (uint256 netAssetAmountOut, uint256 netBrokerFee, uint256 netProtocolFee) {
        if (order.deadline < block.timestamp) revert Errors.Deposit_OrderExpired();

        uint256 sharesToBurn = order.shares;

        if (sharesToBurn == 0) {
            revert Errors.Deposit_InsufficientWithdrawal();
        }

        /// if shares to burn is max uint256, then burn all shares owned by broker
        if (sharesToBurn == type(uint256).max) {
            sharesToBurn = internalVault.balanceOf(broker);
        }

        /// make sure the broker has not exceeded their share burn limit
        if (account.shareMintLimit != type(uint256).max) {
            if (account.totalSharesOutstanding < sharesToBurn) {
                revert Errors.Deposit_ShareBurnLimitExceeded();
            }

            /// update the broker's total shares outstanding
            brokers[order.accountId].account.totalSharesOutstanding -= sharesToBurn;
        }

        /// burn internalVault shares in exchange for liquidity (unit of account) tokens
        uint256 liquidity = internalVault.redeem(sharesToBurn, address(this), broker);

        /// burn liquidity from periphery
        unitOfAccount.burn(address(this), liquidity);

        /// take the withdrawal fees, and return the net liquidity left for the broker
        /// @notice this will consume part of the liquidity that was redeemed
        (uint256 netBrokerFeeInLiquidity, uint256 netProtocolFeeInLiquidity) =
            _calculateWithdrawalFees(account, sharesToBurn, liquidity);

        /// calculate how much asset for this amount of liquidity
        netAssetAmountOut = oracleRouter.getQuote(liquidity, address(unitOfAccount), order.asset);

        /// make sure the withdrawal is above the minimum
        if (netAssetAmountOut < minimumWithdrawal) {
            revert Errors.Deposit_InsufficientWithdrawal();
        }

        /// convert the fees to asset amount
        netBrokerFee = netBrokerFeeInLiquidity.divWadUp(liquidity).mulWadUp(netAssetAmountOut);
        netProtocolFee = netProtocolFeeInLiquidity.divWadUp(liquidity).mulWadUp(netAssetAmountOut);

        /// make sure slippage is acceptable
        ///@notice if minAmountOut is 0, then slippage is not checked
        if (order.minAmountOut != 0 && netAssetAmountOut < order.minAmountOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
        }
    }

    function _distributeFunds(
        address asset,
        address user,
        address broker,
        uint256 toUser,
        uint256 toBroker,
        uint256 toProtocol
    ) private {
        ISafe(fund).transferAssetFromSafeOrRevert(asset, user, toUser);
        if (toBroker > 0) {
            ISafe(fund).transferAssetFromSafeOrRevert(asset, broker, toBroker);
        }
        if (toProtocol > 0) {
            ISafe(fund).transferAssetFromSafeOrRevert(asset, protocolFeeRecipient, toProtocol);
        }
    }

    function _calculateWithdrawalFees(
        BrokerAccountInfo memory account,
        uint256 sharesBurnt,
        uint256 liquidityRedeemed
    ) private pure returns (uint256 netBrokerFee, uint256 netProtocolFee) {
        if (account.brokerPerformanceFeeInBps + account.protocolPerformanceFeeInBps > 0) {
            /// first we must calculate the performance in terms of unit of account
            /// peformance is the difference between the realized share price and the average share buy price
            /// if the realized share price is greater than the average share buy price, then the performance is positive
            /// if the realized share price is less than the average share buy price, then the performance is negative
            /// only take fee if the performance is positive
            /// @notice liquidity is priced in terms of unit of account
            /// @dev Invariant: 1 liquidity = 1 unit of account
            uint256 averageShareBuyPriceInUnitOfAccount =
                account.cumulativeUnitsDeposited.divWadUp(account.cumulativeSharesMinted);
            uint256 realizedSharePriceInUnitOfAccount = liquidityRedeemed.divWad(sharesBurnt);
            uint256 netPerformanceInTermsOfUnitOfAccount = realizedSharePriceInUnitOfAccount
                > averageShareBuyPriceInUnitOfAccount
                ? (realizedSharePriceInUnitOfAccount - averageShareBuyPriceInUnitOfAccount)
                    * sharesBurnt
                : 0;

            /// @notice netPerformance is scaled by WAD
            if (netPerformanceInTermsOfUnitOfAccount > 0) {
                if (account.protocolPerformanceFeeInBps > 0) {
                    netProtocolFee = netPerformanceInTermsOfUnitOfAccount.mulWadUp(
                        account.protocolPerformanceFeeInBps
                    ) / BP_DIVISOR;
                }
                if (account.brokerPerformanceFeeInBps > 0) {
                    netBrokerFee = netPerformanceInTermsOfUnitOfAccount.mulWadUp(
                        account.brokerPerformanceFeeInBps
                    ) / BP_DIVISOR;
                }
            }
        }

        /// Now take the exit fees. Exit fees are taken on the net withdrawal amount.
        if (account.protocolExitFeeInBps > 0) {
            netProtocolFee +=
                liquidityRedeemed.fullMulDivUp(account.protocolExitFeeInBps, BP_DIVISOR);
        }
        if (account.brokerExitFeeInBps > 0) {
            netBrokerFee += liquidityRedeemed.fullMulDivUp(account.brokerExitFeeInBps, BP_DIVISOR);
        }
    }

    function _takeManagementFee() private {
        uint256 timeDelta =
            managementFeeRateInBps > 0 ? block.timestamp - lastManagementFeeTimestamp : 0;
        if (timeDelta > 0) {
            /// update the last management fee timestamp
            lastManagementFeeTimestamp = block.timestamp;

            uint256 totalSupply = internalVault.totalSupply();
            uint256 totalAssets = internalVault.totalAssets();

            /// if the internalVault has no assets, then we don't take any fees
            if (totalAssets == 0 || totalSupply == 0) {
                return;
            }

            /// calculate the annualized management fee rate
            uint256 annualizedFeeRate =
                managementFeeRateInBps.divWad(BP_DIVISOR) * timeDelta / 365 days;
            /// calculate the management fee in shares, remove WAD precision
            /// @notice mulWapUp rounds up in favor of the fee recipient, deter fuckery.
            uint256 managementFeeInShares = totalSupply.mulWadUp(annualizedFeeRate);

            /// mint the management fee to the fee recipient
            internalVault.mintUnbacked(managementFeeInShares, protocolFeeRecipient);
        }
    }

    function _updateVaultBalance() private {
        uint256 assetsInFund =
            oracleRouter.getQuote(internalVault.totalSupply(), fund, address(unitOfAccount));
        uint256 assetsInVault = internalVault.totalAssets();

        /// @notice assetsInFund is part of [0, uint256.max]
        int256 profitDelta = assetsInFund.toInt256() - assetsInVault.toInt256();

        if (profitDelta > 0) {
            /// we transfer the mint into the internalVault
            /// this will distribute the profit to the internalVault's shareholders
            unitOfAccount.mint(address(internalVault), profitDelta.abs());
        } else if (profitDelta < 0) {
            /// if the fund has lost value, we need to account for it
            /// so we decrease the internalVault's total assets to match the fund's total assets
            /// by burning the loss
            unitOfAccount.burn(address(internalVault), profitDelta.abs());
        }
    }

    function getAccountNonce(uint256 accountId_) external view returns (uint256) {
        return brokers[accountId_].account.nonce;
    }

    /// @inheritdoc IPeriphery
    function setProtocolFeeRecipient(address recipient_) external onlyRole(FUND_ROLE) {
        if (recipient_ == address(0)) {
            revert Errors.Deposit_InvalidProtocolFeeRecipient();
        }

        address previous = protocolFeeRecipient;

        /// update the fee recipient
        protocolFeeRecipient = recipient_;

        emit ProtocolFeeRecipientUpdated(recipient_, previous);
    }

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

    /// @inheritdoc IPeriphery
    function setManagementFeeRateInBps(uint256 rateInBps_) external onlyRole(FUND_ROLE) {
        if (rateInBps_ > BP_DIVISOR) {
            revert Errors.Deposit_InvalidManagementFeeRate();
        }

        uint256 previous = managementFeeRateInBps;

        managementFeeRateInBps = rateInBps_;

        emit ManagementFeeRateUpdated(previous, rateInBps_);
    }

    /// @inheritdoc IPeriphery
    function setNetDepositLimit(uint256 limit_) external onlyRole(FUND_ROLE) {
        if (limit_ == 0) {
            revert Errors.Deposit_InvalidNetDepositLimit();
        }

        uint256 previous = netDepositLimit;

        netDepositLimit = limit_;

        emit NetDepositLimitUpdated(previous, limit_);
    }

    /// @inheritdoc IPeriphery
    function getUnitOfAccountToken() external view returns (address) {
        return address(unitOfAccount);
    }

    /// @inheritdoc IPeriphery
    function getVault() external view returns (address) {
        return address(internalVault);
    }

    function enableGlobalAssetPolicy(address asset_, AssetPolicy memory policy_)
        external
        whenNotPaused
        onlyRole(FUND_ROLE)
    {
        if (!policy_.enabled) {
            revert Errors.Deposit_InvalidAssetPolicy();
        }

        assetPolicy[asset_] = policy_;

        emit GlobalAssetPolicyEnabled(asset_, policy_);
    }

    function disableGlobalAssetPolicy(address asset_) external onlyRole(FUND_ROLE) {
        assetPolicy[asset_].enabled = false;

        emit GlobalAssetPolicyDisabled(asset_);
    }

    function getGlobalAssetPolicy(address asset_) external view returns (AssetPolicy memory) {
        return assetPolicy[asset_];
    }

    function enableBrokerAssetPolicy(uint256 accountId_, address asset_, bool isDeposit_)
        external
        whenNotPaused
        onlyRole(FUND_ROLE)
    {
        if (!assetPolicy[asset_].enabled) {
            revert Errors.Deposit_AssetNotSupported();
        }

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

    function disableBrokerAssetPolicy(uint256 accountId_, address asset_, bool isDeposit_)
        external
        onlyRole(FUND_ROLE)
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

    /// @inheritdoc IPeriphery
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

    function closeAccount(uint256 accountId_) public onlyRole(MINTER_ROLE) {
        if (!brokers[accountId_].account.canBeClosed()) {
            revert Errors.Deposit_AccountCannotBeClosed();
        }
        /// @notice this will revert if the token does not exist
        _burn(accountId_);
        brokers[accountId_].account.state = AccountState.CLOSED;
    }

    /// @inheritdoc IPeriphery
    function pauseAccount(uint256 accountId_) public onlyRole(MINTER_ROLE) {
        if (!brokers[accountId_].account.isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }
        if (_ownerOf(accountId_) == address(0)) revert Errors.Deposit_AccountDoesNotExist();
        brokers[accountId_].account.state = AccountState.PAUSED;

        emit AccountPaused(accountId_);
    }

    /// @inheritdoc IPeriphery
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

    /// @inheritdoc IPeriphery
    function getAccountInfo(uint256 accountId_) public view returns (BrokerAccountInfo memory) {
        return brokers[accountId_].account;
    }

    /// @inheritdoc IPeriphery
    function increaseAccountNonce(uint256 accountId_, uint256 increment_) external whenNotPaused {
        if (_ownerOf(accountId_) != msg.sender) revert Errors.Deposit_OnlyAccountOwner();
        if (brokers[accountId_].account.isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }

        brokers[accountId_].account.nonce += increment_ > 1 ? increment_ : 1;
    }

    /// @inheritdoc IPeriphery
    function peekNextTokenId() public view returns (uint256) {
        return tokenId + 1;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function setPauser(address _pauser) external onlyRole(FUND_ROLE) {
        _grantRole(PAUSER_ROLE, _pauser);
    }

    function revokePauser(address _pauser) external onlyRole(FUND_ROLE) {
        _revokeRole(PAUSER_ROLE, _pauser);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return interfaceId == type(IPeriphery).interfaceId || super.supportsInterface(interfaceId);
    }
}
