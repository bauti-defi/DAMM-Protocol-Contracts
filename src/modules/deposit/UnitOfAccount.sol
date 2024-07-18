// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@src/libs/Errors.sol";

contract UnitOfAccount is ERC20 {
    address internal immutable periphery;

    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol, _decimals)
    {
        periphery = msg.sender;
    }

    modifier onlyPeriphery() {
        if (msg.sender != address(periphery)) revert Errors.Deposit_OnlyPeriphery();
        _;
    }

    function mint(address receiver, uint256 amount) public onlyPeriphery {
        _mint(receiver, amount);
    }

    function burn(address owner, uint256 amount) public onlyPeriphery {
        _burn(owner, amount);
    }
}
