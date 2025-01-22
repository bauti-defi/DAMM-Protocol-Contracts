// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import "@solmate/tokens/ERC20.sol";
import "@src/libs/Errors.sol";

/// @title Unit of Account Token
/// @notice An ERC20 token representing a standardized unit of value across different deposit assets
/// @dev Only the periphery contract can mint/burn tokens, which it does in response to deposits/withdrawals
contract UnitOfAccount is ERC20 {
    /// @notice The periphery contract address that has exclusive minting/burning rights
    address internal immutable periphery;

    /// @notice Creates a new Unit of Account token
    /// @param _name The name of the token
    /// @param _symbol The symbol of the token
    /// @param _decimals The number of decimals for the token
    constructor(string memory _name, string memory _symbol, uint8 _decimals)
        ERC20(_name, _symbol, _decimals)
    {
        periphery = msg.sender;
    }

    /// @notice Ensures only the periphery contract can call the modified function
    /// @dev Used to restrict minting and burning rights
    modifier onlyPeriphery() {
        if (msg.sender != address(periphery)) revert Errors.Deposit_OnlyPeriphery();
        _;
    }

    /// @notice Mints new tokens to a specified address
    /// @dev Can only be called by the periphery contract
    /// @param receiver The address to receive the minted tokens
    /// @param amount The amount of tokens to mint
    function mint(address receiver, uint256 amount) public onlyPeriphery {
        _mint(receiver, amount);
    }

    /// @notice Burns tokens from a specified address
    /// @dev Can only be called by the periphery contract
    /// @param owner The address to burn tokens from
    /// @param amount The amount of tokens to burn
    function burn(address owner, uint256 amount) public onlyPeriphery {
        _burn(owner, amount);
    }
}
