// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "@openzeppelin-contracts/token/ERC20/ERC20.sol";
import "@src/interfaces/IFund.sol";

contract DepositWithdrawModule is ERC20 {
    IFund public immutable fund;

    constructor(address fund_, string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        fund = IFund(fund_);
    }

    function deposit(address token, uint256 amount) public {
        // valuate the fund in USD terms

        // valuate deposit amount in USD terms

        // transfer from user to fund

        // check amounts are right

        // mint shares to user
    }

    function withdraw() public {}
}
