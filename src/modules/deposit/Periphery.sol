// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@openzeppelin-contracts/utils/math/Math.sol";
import "@openzeppelin-contracts/token/ERC721/ERC721.sol";
import "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin-contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin-contracts/utils/math/SignedMath.sol";
import "@openzeppelin-contracts/utils/math/SafeCast.sol";
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
    using Math for uint256;
    using SignedMath for int256;

    /// @dev the DAMM fund the periphery is associated with
    IFund public immutable fund;
    /// @dev should be a Euler Oracle Router
    IPriceOracle public immutable oracleRouter;
    /// @dev common unit of account for assets and vault
    UnitOfAccount public immutable unitOfAccount;
    /// @dev used internally for yield accounting
    FundShareVault public immutable vault;

    /// @dev whether the accounts are transferable
    bool public immutable transferable;

    /// @dev the minter role
    address public admin;

    address public feeRecipient;

    mapping(address asset => AssetPolicy policy) private assetPolicy;
    mapping(uint256 tokenId => UserAccountInfo account) private accountInfo;

    uint256 private tokenId = 0;
    bool public paused;

    constructor(
        string memory vaultName_,
        string memory vaultSymbol_,
        uint8 decimals_,
        address fund_,
        address oracleRouter_,
        address admin_,
        address feeRecipient_,
        bool transferable_
    ) ERC721(string.concat(vaultName_, " Account"), string.concat("ACC-", vaultSymbol_)) {
        if (fund_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (oracleRouter_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (admin_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }
        if (feeRecipient_ == address(0)) {
            revert Errors.Deposit_InvalidConstructorParam();
        }

        fund = IFund(fund_);
        oracleRouter = IPriceOracle(oracleRouter_);
        admin = admin_;
        feeRecipient = feeRecipient_;
        transferable = transferable_;
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
    /// if this invariant is violated, we are fucked.
    modifier updateBalances() {
        uint256 assetsInFund = oracleRouter.getQuote(0, address(fund), address(unitOfAccount));
        uint256 assetsInVault = vault.totalAssets();

        int256 profitDelta = assetsInFund.toInt256() - assetsInVault.toInt256();

        if (profitDelta > 0) {
            unitOfAccount.mint(address(this), profitDelta.abs());

            /// we transfer the profit into the vault
            /// this will distribute the profit to the vault's shareholders
            if (!unitOfAccount.transfer(address(vault), profitDelta.abs())) {
                revert Errors.Deposit_AssetTransferFailed();
            }
        } else if (profitDelta < 0) {
            /// if the fund has lost value, we need to account for it
            /// so we decrease the vault's total assets to match the fund's total assets
            /// by burning the loss
            unitOfAccount.burn(address(vault), profitDelta.abs());
        }

        _;

        /// invariants for 'some' peace of mind
        assetsInFund = oracleRouter.getQuote(0, address(fund), address(unitOfAccount));
        assetsInVault = vault.totalAssets();
        if (unitOfAccount.totalSupply() != assetsInVault) {
            revert Errors.Deposit_SupplyInvariantViolated();
        }
        if (assetsInFund != assetsInVault) {
            revert Errors.Deposit_AssetInvariantViolated();
        }
    }

    /// @dev this modifier ensures that the account info is zeroed out if the user has no shares outstanding
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
        updateBalances
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

        sharesOut = _deposit(order.intent.deposit, minter);

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            ERC20(order.intent.deposit.asset).safeTransferFrom(
                minter, msg.sender, order.intent.relayerTip
            );
        }

        emit Deposit(
            order.intent.deposit.accountId,
            order.intent.deposit.asset,
            order.intent.deposit.amount,
            sharesOut,
            order.intent.relayerTip
        );
    }

    function deposit(DepositOrder calldata order)
        public
        notPaused
        nonReentrant
        updateBalances
        returns (uint256 sharesOut)
    {
        address minter = _ownerOf(order.accountId);
        if (minter == address(0)) {
            revert Errors.Deposit_AccountDoesNotExist();
        }

        if (minter != msg.sender) {
            revert Errors.Deposit_OnlyAccountOwner();
        }

        sharesOut = _deposit(order, minter);

        emit Deposit(order.accountId, order.asset, order.amount, sharesOut, 0);
    }

    function _deposit(DepositOrder calldata order, address user)
        private
        returns (uint256 sharesOut)
    {
        AssetPolicy memory policy = assetPolicy[order.asset];

        if (order.deadline < block.timestamp) {
            revert Errors.Deposit_OrderExpired();
        }

        UserAccountInfo memory account = accountInfo[order.accountId];

        if (!account.isActive()) revert Errors.Deposit_AccountNotActive();

        if (account.isExpired()) {
            revert Errors.Deposit_AccountExpired();
        }

        if (!policy.canDeposit || !policy.enabled) {
            revert Errors.Deposit_AssetUnavailable();
        }

        if (policy.permissioned && !account.isSuperUser()) {
            revert Errors.Deposit_OnlySuperUser();
        }

        uint256 assetAmountIn = order.amount;
        ERC20 assetToken = ERC20(order.asset);

        /// if amount is 0, then deposit the user's entire balance
        if (assetAmountIn == 0) {
            assetAmountIn = assetToken.balanceOf(user);
        }

        /// transfer asset from user to fund
        assetToken.safeTransferFrom(user, address(fund), assetAmountIn);

        /// calculate how much liquidity for this amount of deposited asset
        uint256 liquidity =
            oracleRouter.getQuote(assetAmountIn, order.asset, address(unitOfAccount));

        /// make sure the deposit is above the minimum
        if (liquidity < policy.minimumDeposit) {
            revert Errors.Deposit_InsufficientDeposit();
        }

        /// mint liquidity to periphery
        unitOfAccount.mint(address(this), liquidity);

        /// mint shares to user using the liquidity that was just minted to periphery
        sharesOut = vault.deposit(liquidity, order.recipient);

        /// lets make sure slippage is acceptable
        if (sharesOut < order.minSharesOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
        }

        /// make sure the user hasn't exceeded their share mint limit
        if (account.totalSharesOutstanding + sharesOut > account.shareMintLimit) {
            revert Errors.Deposit_ShareMintLimitExceeded();
        }

        /// update the user's cumulative units deposited
        accountInfo[order.accountId].cumulativeUnitsDeposited += liquidity;

        /// update the user's total shares outstanding
        accountInfo[order.accountId].totalSharesOutstanding += sharesOut;

        /// update the user's cumulative shares minted
        accountInfo[order.accountId].cumulativeSharesMinted += sharesOut;
    }

    function withdraw(SignedWithdrawIntent calldata order)
        public
        notPaused
        nonReentrant
        updateBalances
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

        /// withdraw liquidity from vault
        assetAmountOut = _withdraw(order.intent.withdraw, burner);

        /// pay the relayer if required
        if (order.intent.relayerTip > 0) {
            if (order.intent.relayerTip >= assetAmountOut) {
                revert Errors.Deposit_InsufficientAmount();
            }

            _transferAssetFromFund(order.intent.withdraw.asset, msg.sender, order.intent.relayerTip);
        }

        /// transfer asset from fund to receiver
        _transferAssetFromFund(
            order.intent.withdraw.asset,
            order.intent.withdraw.to,
            assetAmountOut - order.intent.relayerTip
        );

        emit Withdraw(
            order.intent.withdraw.accountId,
            order.intent.withdraw.asset,
            order.intent.withdraw.shares,
            assetAmountOut,
            order.intent.relayerTip
        );
    }

    function withdraw(WithdrawOrder calldata order)
        public
        notPaused
        nonReentrant
        updateBalances
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

        assetAmountOut = _withdraw(order, burner);

        /// transfer asset from fund to receiver
        _transferAssetFromFund(order.asset, order.to, assetAmountOut);

        emit Withdraw(order.accountId, order.asset, order.shares, assetAmountOut, 0);
    }

    function _withdraw(WithdrawOrder calldata order, address user)
        private
        returns (uint256 assetAmountOut)
    {
        if (order.deadline < block.timestamp) revert Errors.Deposit_OrderExpired();

        AssetPolicy memory policy = assetPolicy[order.asset];

        if (!policy.canWithdraw || !policy.enabled) {
            revert Errors.Deposit_AssetUnavailable();
        }

        UserAccountInfo memory account = accountInfo[order.accountId];

        if (policy.permissioned && !account.isSuperUser()) {
            revert Errors.Deposit_OnlySuperUser();
        }

        if (!account.isActive()) revert Errors.Deposit_AccountNotActive();

        if (account.isExpired()) {
            revert Errors.Deposit_AccountExpired();
        }

        uint256 sharesToBurn = order.shares;

        if (sharesToBurn == 0) {
            revert Errors.Deposit_InsufficientWithdrawal();
        }

        /// if shares to burn is max uint256, then burn all shares owned by user
        if (sharesToBurn == type(uint256).max) {
            sharesToBurn = vault.balanceOf(user);
        }

        /// update the user's total shares outstanding
        if (account.shareMintLimit != type(uint256).max) {
            /// make sure the user has not exceeded their share burn limit
            if (account.totalSharesOutstanding < sharesToBurn) {
                revert Errors.Deposit_ShareBurnLimitExceeded();
            }

            accountInfo[order.accountId].totalSharesOutstanding -= sharesToBurn;
        }

        uint256 performanceInTermsOfUnitOfAccount;

        /// only take fee if the fee is greater than 0
        if (account.feeBps > 0) {
            uint8 _vaultDecimals = vault.decimals();

            /// use precision for calculations
            uint256 averageShareBuyPriceInUnitOfAccount =
                account.cumulativeUnitsDeposited.mulDiv(PRECISION, account.cumulativeSharesMinted);
            uint256 currentSharePriceInUnitOfAccount =
                vault.previewRedeem(10 ** _vaultDecimals).mulDiv(PRECISION, 10 ** _vaultDecimals);

            /// @notice removing precision from the output
            uint256 netPerformanceInTermsOfUnitOfAccount = currentSharePriceInUnitOfAccount
                > averageShareBuyPriceInUnitOfAccount
                ? sharesToBurn.mulDiv(
                    currentSharePriceInUnitOfAccount - averageShareBuyPriceInUnitOfAccount, PRECISION
                )
                : 0;

            /// skim the fee from the net performance
            if (netPerformanceInTermsOfUnitOfAccount > 0) {
                performanceInTermsOfUnitOfAccount =
                    netPerformanceInTermsOfUnitOfAccount.mulDiv(account.feeBps, BP_DIVISOR);
            }
        }

        /// burn vault shares in exchange for liquidity (unit of account) tokens
        uint256 liquidity = vault.redeem(sharesToBurn, address(this), user);

        /// make sure the withdrawal is above the minimum
        if (liquidity < policy.minimumWithdrawal) {
            revert Errors.Deposit_InsufficientWithdrawal();
        }

        if (performanceInTermsOfUnitOfAccount > 0) {
            liquidity -= performanceInTermsOfUnitOfAccount;
            vault.deposit(performanceInTermsOfUnitOfAccount, feeRecipient);
        }

        /// burn liquidity from periphery
        unitOfAccount.burn(address(this), liquidity);

        /// calculate how much asset for this amount of liquidity
        assetAmountOut = oracleRouter.getQuote(liquidity, address(unitOfAccount), order.asset);

        /// make sure slippage is acceptable
        /// TODO: make this use type(uint256).max instead of 0
        ///@notice if minAmountOut is 0, then slippage is not checked
        if (order.minAmountOut != 0 && assetAmountOut < order.minAmountOut) {
            revert Errors.Deposit_SlippageLimitExceeded();
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

    function getAccountNonce(uint256 accountId_) external view returns (uint256) {
        return accountInfo[accountId_].nonce;
    }

    function _setFeeRecipient(address recipient_) private {
        if (recipient_ == address(0)) {
            revert Errors.Deposit_InvalidFeeRecipient();
        }

        address previous = feeRecipient;

        /// update the fee recipient
        feeRecipient = recipient_;

        emit FeeRecipientUpdated(recipient_, previous);
    }

    function setFeeRecipient(address recipient_) external onlyFund {
        _setFeeRecipient(recipient_);
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
        if (!transferable) revert Errors.Deposit_AccountNotTransferable();

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
        if (params_.feeBps >= BP_DIVISOR) {
            revert Errors.Deposit_InvalidPerformanceFee();
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

        accountInfo[nextTokenId] = UserAccountInfo({
            role: params_.role,
            state: AccountState.ACTIVE,
            expirationTimestamp: block.timestamp + params_.ttl,
            nonce: 0,
            feeBps: params_.feeBps,
            shareMintLimit: params_.shareMintLimit,
            cumulativeSharesMinted: 0,
            cumulativeUnitsDeposited: 0,
            totalSharesOutstanding: 0
        });

        emit AccountOpened(
            nextTokenId,
            params_.role,
            block.timestamp + params_.ttl,
            params_.shareMintLimit,
            params_.feeBps
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

    function getAccountInfo(uint256 accountId_) public view returns (UserAccountInfo memory) {
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
