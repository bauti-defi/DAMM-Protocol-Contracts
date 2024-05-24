// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

string constant InvalidSignature_Error = "Signature is invalid";
string constant InvalidNonce_Error = "Nonce is invalid";
string constant IntentExpired_Error = "Intent has expired";
string constant InsufficientAmount_Error = "Amount is insufficient";
string constant InsufficientDeposit_Error = "Deposit amount is insufficient";
string constant InsufficientWithdraw_Error = "Withdraw amount is insufficient";
string constant SlippageLimit_Error = "Slippage limit exceeded";
string constant InvalidOracle_Error = "Oracle is invalid";
string constant UnExpectedSupplyIncrease_Error = "Unexpected supply increase";

string constant AssetTransfer_Error = "Asset transfer failed";
string constant AssetUnavailable_Error = "Asset is not enabled";

string constant AccountNotPaused_Error = "Account status: not paused";
string constant AccountNotActive_Error = "Account status: not active";
string constant AccountNull_Error = "Account does not exist";
string constant AccountExists_Error = "Account already exists";
string constant AccountEpochUpToDate_Error = "Account epoch is up to date";

string constant OnlyFeeRecipient_Error = "Caller is not fee recipient";
string constant OnlyFund_Error = "Caller is not fund";
string constant OnlyUser_Error = "Caller is not registered user";
string constant OnlySuperUser_Error = "Caller is not super user";

string constant EpochsEmpty_Error = "No epochs have been created";
string constant EpochEnded_Error = "Epoch has ended";
string constant ActiveEpoch_Error = "Epoch is active";

string constant PerfomanceFeeIsZero_Error = "Performance fee is zero";

string constant NonZeroValueExpected_Error = "Non-zero value expected";
