// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@openzeppelin-contracts/token/ERC721/ERC721.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin-contracts/utils/math/SignedMath.sol";
import "@openzeppelin-contracts/utils/math/SafeCast.sol";
import "@solady/utils/FixedPointMathLib.sol";
import "@solmate/utils/SafeTransferLib.sol";
import "@solady/utils/ReentrancyGuard.sol";
import "@src/libs/Constants.sol";
import "@src/interfaces/IFund.sol";

import "@src/libs/Errors.sol";
import "@src/interfaces/IPeriphery.sol";
import "./UnitOfAccount.sol";
import {FundShareVault} from "./FundShareVault.sol";

contract Periphery is ERC721, ReentrancyGuard, IPeriphery {
    using SafeTransferLib for ERC20;
    using SafeCast for uint256;
    using MessageHashUtils for bytes;
    using SignedMath for int256;
    using FixedPointMathLib for uint256;

    /// @dev the DAMM fund the periphery is associated with
    IFund public immutable fund;
    /// @dev should be a Euler Oracle Router
    IPriceOracle public immutable oracleRouter;
    /// @dev common unit of account for assets and vault
    UnitOfAccount public immutable unitOfAccount;
    /// @dev used internally for yield accounting
    FundShareVault public immutable vault;

    /// @dev the minter role
    address public admin;

    /// @dev the recipient of the protocol fees
    address public protocolFeeRecipient;
    uint256 private lastManagementFeeTimestamp;
    uint256 public managementFeeRateInBps;

    mapping(address asset => AssetPolicy policy) private assetPolicy;
    mapping(uint256 tokenId => BrokerAccountInfo account) private accountInfo;

    uint256 private tokenId = 0;
    bool public paused;

    constructor(
        string memory vaultName_,
        string memory vaultSymbol_,
        uint8 decimals_,
        address fund_,
        address oracleRouter_,
        address admin_,
        address protocolFeeRecipient_,
        uint256 managementFeeRateInBps_
    ) ERC721(vaultName_, vaultSymbol_) {
        if (fund_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (oracleRouter_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (admin_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (protocolFeeRecipient_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (managementFeeRateInBps_ >= BP_DIVISOR) {
            revert Errors.Deposit_InvalidConstructorParam();
        }

        fund = IFund(fund_);
        oracleRouter = IPriceOracle(oracleRouter_);
        admin = admin_;
        protocolFeeRecipient = protocolFeeRecipient_;
        managementFeeRateInBps = managementFeeRateInBps_;
        lastManagementFeeTimestamp = block.timestamp;
        unitOfAccount = new UnitOfAccount("Liquidity", "UNIT", decimals_);
        vault = new FundShareVault(address(unitOfAccount), vaultName_, vaultSymbol_);

        /// @notice infinite approval for the vault to manage periphery's balance
        unitOfAccount.approve(address(vault), type(uint256).max);
    }

    modifier notPaused() {
        if (paused) revert Errors.Deposit_ModulePaused();
        _;
    }

    modifier onlyFund() {
        if (msg.sender != address(fund)) revert Errors.OnlyFund();
        _;
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert Errors.OnlyAdmin();
        _;
    }

    /// @dev This modifier updates the balances of the vault and the fund
    /// this ensures that the vault's total assets are always equal to the fund's total assets
    modifier rebalanceVault() {
        _updateVaultBalance();

        _;

        _updateVaultBalance();
    }

    /// @dev this modifier ensures that the account info is zeroed out if the broker has no shares outstanding
    modifier zeroOutAccountInfo(uint256 accountId_) {
        _;
        if (accountInfo[accountId_].totalSharesOutstanding == 0) {
            accountInfo[accountId_].cumulativeSharesMinted = 0;
            accountInfo[accountId_].cumulativeUnitsDeposited = 0;
        }
    }

    function deposit(SignedDepositIntent calldata order)
        public
        notPaused
        nonReentrant
        rebalanceVault
        returns (uint256 sharesOut)
    {
        address minter = _ownerOf(order.intent.deposit.accountId);
        if (minter == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }

        if (
            !SignatureChecker.isValidSignatureNow(
                minter, abi.encode(order.intent).toEthSignedMessageHash(), order.signature
            )
        ) revert Errors.Deposit_InvalidSignature();

        if (order.intent.nonce != accountInfo[order.intent.deposit.accountId].nonce++) {
            revert Errors.Deposit_InvalidNonce();
        }

        if (order.intent.chaindId != block.chainid) revert Errors.Deposit_InvalidChain();

        /// @notice The management fee should be charged before the deposit is processed
        /// otherwise, the management fee will be charged on the deposit amount
        _takeManagementFee();

        AssetPolicy memory policy = assetPolicy[order.intent.deposit.asset];
        BrokerAccountInfo memory account = accountInfo[order.intent.deposit.accountId];

        _validateAccountAssetPolicy(policy, account, true);

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            ERC20(order.intent.deposit.asset).safeTransferFrom(
                minter, msg.sender, order.intent.relayerTip
            );
        }

        /// bribe the fund if required
        if (order.intent.bribe > 0) {
            ERC20(order.intent.deposit.asset).safeTransferFrom(
                minter, address(fund), order.intent.bribe
            );
        }

        sharesOut = _deposit(
            order.intent.deposit,
            minter,
            policy.minimumDeposit,
            account.totalSharesOutstanding,
            account.shareMintLimit,
            account.brokerEntranceFeeInBps,
            account.protocolEntranceFeeInBps
        );

        emit Deposit(
            order.intent.deposit.accountId,
            order.intent.deposit.asset,
            order.intent.deposit.amount,
            sharesOut,
            order.intent.relayerTip,
            order.intent.bribe
        );
    }

    function deposit(DepositOrder calldata order)
        public
        notPaused
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
        BrokerAccountInfo memory account = accountInfo[order.accountId];

        _validateAccountAssetPolicy(policy, account, true);

        sharesOut = _deposit(
            order,
            minter,
            policy.minimumDeposit,
            account.totalSharesOutstanding,
            account.shareMintLimit,
            account.brokerEntranceFeeInBps,
            account.protocolEntranceFeeInBps
        );

        emit Deposit(order.accountId, order.asset, order.amount, sharesOut, 0, 0);
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
        assetToken.safeTransferFrom(broker, address(fund), assetAmountIn);

        /// calculate how much liquidity for this amount of deposited asset
        uint256 liquidity =
            oracleRouter.getQuote(assetAmountIn, order.asset, address(unitOfAccount));

        /// mint liquidity to periphery
        unitOfAccount.mint(address(this), liquidity);

        /// mint shares to the periphery using the liquidity that was just minted
        sharesOut = vault.deposit(liquidity, address(this));

        /// lets make sure slippage is acceptable
        if (sharesOut < order.minSharesOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
        }

        /// make sure the broker hasn't exceeded their share mint limit
        if (totalSharesOutstanding + sharesOut > shareMintLimit) {
            revert Errors.Deposit_ShareMintLimitExceeded();
        }

        /// take the broker entrance fees
        if (brokerEntranceFeeInBps > 0) {
            vault.transfer(broker, sharesOut.fullMulDivUp(brokerEntranceFeeInBps, BP_DIVISOR));
        }

        /// take the protocol entrance fees
        if (protocolEntranceFeeInBps > 0) {
            vault.transfer(
                protocolFeeRecipient, sharesOut.fullMulDivUp(protocolEntranceFeeInBps, BP_DIVISOR)
            );
        }

        /// forward the remaining shares to the broker
        vault.transfer(order.recipient, vault.balanceOf(address(this)));

        /// update the broker's cumulative units deposited
        accountInfo[order.accountId].cumulativeUnitsDeposited += liquidity;

        /// update the broker's total shares outstanding
        accountInfo[order.accountId].totalSharesOutstanding += sharesOut;

        /// update the broker's cumulative shares minted
        accountInfo[order.accountId].cumulativeSharesMinted += sharesOut;
    }

    function withdraw(SignedWithdrawIntent calldata order)
        public
        notPaused
        nonReentrant
        rebalanceVault
        zeroOutAccountInfo(order.intent.withdraw.accountId)
        returns (uint256 assetAmountOut)
    {
        address burner = _ownerOf(order.intent.withdraw.accountId);
        if (burner == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }
        if (
            !SignatureChecker.isValidSignatureNow(
                burner, abi.encode(order.intent).toEthSignedMessageHash(), order.signature
            )
        ) revert Errors.Deposit_InvalidSignature();

        if (order.intent.nonce != accountInfo[order.intent.withdraw.accountId].nonce++) {
            revert Errors.Deposit_InvalidNonce();
        }

        if (order.intent.chaindId != block.chainid) revert Errors.Deposit_InvalidChain();

        AssetPolicy memory policy = assetPolicy[order.intent.withdraw.asset];
        BrokerAccountInfo memory account = accountInfo[order.intent.withdraw.accountId];

        _validateAccountAssetPolicy(policy, account, false);

        (uint256 netAssetAmountOut, uint256 netBrokerFee, uint256 netProtocolFee) =
            _withdraw(burner, order.intent.withdraw, account, policy.minimumWithdrawal);

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
            _transferAssetFromFund(order.intent.withdraw.asset, msg.sender, order.intent.relayerTip);
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
            order.intent.bribe
        );
    }

    function withdraw(WithdrawOrder calldata order)
        public
        notPaused
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
        BrokerAccountInfo memory account = accountInfo[order.accountId];

        _validateAccountAssetPolicy(policy, account, false);

        (uint256 netAssetAmountOut, uint256 netBrokerFee, uint256 netProtocolFee) =
            _withdraw(burner, order, account, policy.minimumWithdrawal);

        assetAmountOut = netAssetAmountOut - netBrokerFee - netProtocolFee;

        /// distribute the funds to the user, broker, and protocol
        _distributeFunds(
            order.asset, order.to, burner, assetAmountOut, netBrokerFee, netProtocolFee
        );

        emit Withdraw(order.accountId, order.asset, order.shares, netAssetAmountOut, 0, 0);
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
            sharesToBurn = vault.balanceOf(broker);
        }

        /// make sure the broker has not exceeded their share burn limit
        if (account.shareMintLimit != type(uint256).max) {
            if (account.totalSharesOutstanding < sharesToBurn) {
                revert Errors.Deposit_ShareBurnLimitExceeded();
            }

            /// update the broker's total shares outstanding
            accountInfo[order.accountId].totalSharesOutstanding -= sharesToBurn;
        }

        /// burn vault shares in exchange for liquidity (unit of account) tokens
        uint256 liquidity = vault.redeem(sharesToBurn, address(this), broker);

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
        /// TODO: make this use type(uint256).max instead of 0
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
        _transferAssetFromFund(asset, user, toUser);
        if (toBroker > 0) {
            _transferAssetFromFund(asset, broker, toBroker);
        }
        if (toProtocol > 0) {
            _transferAssetFromFund(asset, protocolFeeRecipient, toProtocol);
        }
    }

    function _calculateWithdrawalFees(
        BrokerAccountInfo memory account,
        uint256 sharesBurnt,
        uint256 liquidityRedeemed
    ) private returns (uint256 netBrokerFee, uint256 netProtocolFee) {
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
            ? (realizedSharePriceInUnitOfAccount - averageShareBuyPriceInUnitOfAccount) * sharesBurnt
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

            /// calculate the annualized management fee rate
            uint256 annualizedFeeRate =
                managementFeeRateInBps.divWad(BP_DIVISOR) * timeDelta / 365 days;
            /// calculate the management fee in shares, remove WAD precision
            /// @notice mulWapUp rounds up in favor of the fee recipient, deter fuckery.
            uint256 managementFeeInShares = vault.totalSupply().mulWadUp(annualizedFeeRate);

            /// mint the management fee to the fee recipient
            vault.mint(managementFeeInShares, protocolFeeRecipient);
        }
    }

    function _transferAssetFromFund(address asset_, address to_, uint256 amount_) private {
        /// call fund to transfer asset out
        (bool success, bytes memory returnData) = fund.execTransactionFromModuleReturnData(
            asset_,
            0,
            abi.encodeWithSignature("transfer(address,uint256)", to_, amount_),
            Enum.Operation.Call
        );

        /// check transfer was successful
        if (!success || (returnData.length > 0 && !abi.decode(returnData, (bool)))) {
            revert Errors.Deposit_AssetTransferFailed();
        }
    }

    function _validateAccountAssetPolicy(
        AssetPolicy memory policy,
        BrokerAccountInfo memory account,
        bool isDeposit
    ) private view {
        if (!account.isActive()) revert Errors.Deposit_AccountNotActive();

        if (account.isExpired() && isDeposit) {
            revert Errors.Deposit_AccountExpired();
        }

        if (
            (!policy.canDeposit && isDeposit) || (!policy.canWithdraw && !isDeposit)
                || !policy.enabled
        ) {
            revert Errors.Deposit_AssetUnavailable();
        }

        if (policy.permissioned && !account.isSuperUser()) {
            revert Errors.Deposit_OnlySuperUser();
        }
    }

    function _updateVaultBalance() private {
        uint256 assetsInFund = oracleRouter.getQuote(0, address(fund), address(unitOfAccount));
        uint256 assetsInVault = vault.totalAssets();

        /// @notice assetsInFund is part of [0, uint256.max]
        int256 profitDelta = assetsInFund.toInt256() - assetsInVault.toInt256();

        if (profitDelta > 0) {
            /// we transfer the mint into the vault
            /// this will distribute the profit to the vault's shareholders
            unitOfAccount.mint(address(vault), profitDelta.abs());
        } else if (profitDelta < 0) {
            /// if the fund has lost value, we need to account for it
            /// so we decrease the vault's total assets to match the fund's total assets
            /// by burning the loss
            unitOfAccount.burn(address(vault), profitDelta.abs());
        }
    }

    function getAccountNonce(uint256 accountId_) external view returns (uint256) {
        return accountInfo[accountId_].nonce;
    }

    function setProtocolFeeRecipient(address recipient_) external onlyFund {
        if (recipient_ == address(0)) {
            revert Errors.Deposit_InvalidProtocolFeeRecipient();
        }

        address previous = protocolFeeRecipient;

        /// update the fee recipient
        protocolFeeRecipient = recipient_;

        emit ProtocolFeeRecipientUpdated(recipient_, previous);
    }

    function setManagementFeeRateInBps(uint256 rateInBps_) external onlyFund {
        if (rateInBps_ > BP_DIVISOR) {
            revert Errors.Deposit_InvalidManagementFeeRate();
        }

        uint256 previous = managementFeeRateInBps;

        managementFeeRateInBps = rateInBps_;

        emit ManagementFeeRateUpdated(previous, rateInBps_);
    }

    function _setAdmin(address admin_) private {
        if (admin_ == address(0)) {
            revert Errors.Deposit_InvalidAdmin();
        }

        address previous = admin;

        /// update the admin
        admin = admin_;

        emit AdminUpdated(admin_, previous);
    }

    function setAdmin(address admin_) external onlyFund {
        _setAdmin(admin_);
    }

    function enableAsset(address asset_, AssetPolicy memory policy_) external notPaused onlyFund {
        if (!fund.isAssetOfInterest(asset_)) {
            revert Errors.Deposit_AssetNotSupported();
        }
        if (!policy_.enabled) {
            revert Errors.Deposit_InvalidAssetPolicy();
        }

        assetPolicy[asset_] = policy_;

        emit AssetEnabled(asset_, policy_);
    }

    function disableAsset(address asset_) external onlyFund {
        assetPolicy[asset_].enabled = false;

        emit AssetDisabled(asset_);
    }

    function getAssetPolicy(address asset_) external view returns (AssetPolicy memory) {
        return assetPolicy[asset_];
    }

    /// @notice restricting the transfer makes this a soulbound token
    function transferFrom(address from_, address to_, uint256 tokenId_) public override {
        if (!accountInfo[tokenId_].transferable) revert Errors.Deposit_AccountNotTransferable();

        super.transferFrom(from_, to_, tokenId_);
    }

    function openAccount(CreateAccountParams calldata params_)
        public
        notPaused
        nonReentrant
        onlyAdmin
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
        if (params_.role == Role.NONE) {
            revert Errors.Deposit_InvalidRole();
        }
        if (params_.ttl == 0) {
            revert Errors.Deposit_InvalidTTL();
        }
        if (params_.shareMintLimit == 0) {
            revert Errors.Deposit_InvalidShareMintLimit();
        }

        unchecked {
            nextTokenId = ++tokenId;
        }

        /// @notice If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
        _safeMint(params_.user, nextTokenId);

        accountInfo[nextTokenId] = BrokerAccountInfo({
            transferable: params_.transferable,
            role: params_.role,
            state: AccountState.ACTIVE,
            expirationTimestamp: block.timestamp + params_.ttl,
            nonce: 0,
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
            params_.role,
            block.timestamp + params_.ttl,
            params_.shareMintLimit,
            params_.transferable
        );
    }

    function closeAccount(uint256 accountId_) public onlyAdmin {
        if (!accountInfo[accountId_].canBeClosed()) revert Errors.Deposit_AccountCannotBeClosed();
        /// @notice this will revert if the token does not exist
        _burn(accountId_);
        accountInfo[accountId_].state = AccountState.CLOSED;
    }

    function pauseAccount(uint256 accountId_) public onlyAdmin {
        if (!accountInfo[accountId_].isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }
        if (_ownerOf(accountId_) == address(0)) revert Errors.Deposit_AccountDoesNotExist();
        accountInfo[accountId_].state = AccountState.PAUSED;

        emit AccountPaused(accountId_);
    }

    function unpauseAccount(uint256 accountId_) public notPaused onlyAdmin {
        if (!accountInfo[accountId_].isPaused()) {
            revert Errors.Deposit_AccountNotPaused();
        }
        if (_ownerOf(accountId_) == address(0)) revert Errors.Deposit_AccountDoesNotExist();
        accountInfo[accountId_].state = AccountState.ACTIVE;

        /// increase nonce to avoid replay attacks
        accountInfo[accountId_].nonce++;

        emit AccountUnpaused(accountId_);
    }

    function getAccountInfo(uint256 accountId_) public view returns (BrokerAccountInfo memory) {
        return accountInfo[accountId_];
    }

    function increaseAccountNonce(uint256 accountId_, uint256 increment_) external notPaused {
        if (_ownerOf(accountId_) != msg.sender) revert Errors.Deposit_OnlyAccountOwner();
        if (accountInfo[accountId_].isActive()) {
            revert Errors.Deposit_AccountNotActive();
        }

        accountInfo[accountId_].nonce += increment_ > 1 ? increment_ : 1;
    }

    function peekNextTokenId() public view returns (uint256) {
        return tokenId + 1;
    }

    function fundIsOpen() external view returns (bool) {
        return !fund.hasOpenPositions();
    }

    function pause() external onlyFund {
        paused = true;

        emit Paused();
    }

    function unpause() external onlyFund {
        paused = false;

        emit Unpaused();
    }
}
