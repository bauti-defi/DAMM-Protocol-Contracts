// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@openzeppelin-contracts/access/Ownable.sol";
import "@src/libs/Errors.sol";

/// @title Unit of Account Token
/// @notice An ERC20 token representing a standardized unit of value across different deposit assets
/// @dev Only the periphery contract can mint/burn tokens, which it does in response to deposits/withdrawals
contract UnitOfAccount is ERC20, Ownable {
    /// @notice The deposit module contract address that has exclusive minting/burning rights
    address public immutable controller;

    /// @notice Creates a new Unit of Account token
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @param _decimals The number of decimals for the token
    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol, _decimals)
        Ownable(msg.sender)
    {
        controller = msg.sender;
    }

    /// @notice Mints new tokens to a specified address
    /// @dev Can only be called by the periphery contract
    /// @param receiver The address to receive the minted tokens
    /// @param amount The amount of tokens to mint
    function mint(address receiver, uint256 amount) public onlyOwner {
        _mint(receiver, amount);
    }

    /// @notice Burns tokens from a specified address
    /// @dev Can only be called by the periphery contract
    /// @param owner The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burn(address owner, uint256 amount) public onlyOwner {
        _burn(owner, amount);
    }
}
