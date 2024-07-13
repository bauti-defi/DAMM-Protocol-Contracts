// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";

import {OnlyPeriphery_Error} from "./Errors.sol";

contract UnitOfAccount is ERC20 {
    address internal immutable periphery;

    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol, _decimals)
    {
        periphery = msg.sender;
    }

    modifier onlyPeriphery() {
        require(msg.sender == address(periphery), OnlyPeriphery_Error);
        _;
    }

    function mint(address receiver, uint256 amount) public onlyPeriphery returns (bool) {
        _mint(receiver, amount);
        return true;
    }

    function burn(address owner, uint256 amount) public onlyPeriphery returns (bool) {
        _burn(owner, amount);
        return true;
    }
}
