// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20Permit} from "@openzeppelin-contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin-contracts/access/Ownable.sol";
import "@src/libs/Errors.sol";

/// @title Fund Share Vault
/// @notice An ERC4626 vault that tokenizes shares in the fund
/// @dev All operations are restricted to the periphery contract to ensure proper accounting
contract FundShareVault is ERC4626, ERC20Permit, Ownable {
    /// @notice The deposit module contract address that has exclusive operation rights
    address public immutable controller;

    /// @notice The decimal offset to mitigate share inflation attacks
    uint8 public immutable decimalsOffset;

    /// @notice Creates a new Fund Share Vault
    /// @param _unitOfAccount The underlying unit of account token
    /// @param _name The name of the vault shares token
    /// @param _symbol The symbol of the vault shares token
    /// @param __decimalsOffset The decimal offset to mitigate share inflation attacks
    constructor(
        address _unitOfAccount,
        string memory _name,
        string memory _symbol,
        uint8 __decimalsOffset
    )
        ERC4626(IERC20(_unitOfAccount))
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        Ownable(msg.sender)
    {
        controller = msg.sender;
        decimalsOffset = __decimalsOffset;
    }

    /// @notice Deposits assets into the vault
    /// @dev Can only be called by the periphery contract
    /// @param assets Amount of assets to deposit
    /// @param receiver Address to receive the minted shares
    /// @return shares Amount of shares minted
    function deposit(uint256 assets, address receiver)
        public
        override
        onlyOwner
        returns (uint256 shares)
    {
        shares = super.deposit(assets, receiver);
    }

    /// @notice Mints shares from the vault
    /// @dev Can only be called by the periphery contract
    /// @param shares Amount of shares to mint
    /// @param receiver Address to receive the minted shares
    /// @return assets Amount of assets deposited
    function mint(uint256 shares, address receiver)
        public
        override
        onlyOwner
        returns (uint256 assets)
    {
        assets = super.mint(shares, receiver);
    }

    /// @notice Redeems shares from the vault
    /// @dev Can only be called by the periphery contract
    /// @param shares Amount of shares to redeem
    /// @param receiver Address to receive the assets
    /// @param owner Address that owns the shares
    /// @return assets Amount of assets withdrawn
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        onlyOwner
        returns (uint256 assets)
    {
        assets = super.redeem(shares, receiver, owner);
    }

    /// @notice Withdraws assets from the vault
    /// @dev Can only be called by the periphery contract
    /// @param assets Amount of assets to withdraw
    /// @param receiver Address to receive the assets
    /// @param owner Address that owns the shares
    /// @return shares Amount of shares burned
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        onlyOwner
        returns (uint256 shares)
    {
        shares = super.withdraw(assets, receiver, owner);
    }

    /// @notice Mints shares without requiring a deposit of underlying assets
    /// @dev Used for fee distributions and other share dilution events
    /// @param shares Amount of shares to mint
    /// @param receiver Address to receive the shares
    function mintUnbacked(uint256 shares, address receiver) public onlyOwner {
        _mint(receiver, shares);
    }

    /// @notice Returns the number of decimals of the vault shares
    /// @dev Overrides to inherit the ERC4626 decimals function implementation
    function decimals() public view override(ERC4626, ERC20) returns (uint8) {
        return super.decimals();
    }

    /// @notice Returns the decimal offset used to mitigate share inflation attacks
    /// @dev Overrides the ERC4626 _decimalsOffset function
    /// @return offset The decimal offset
    function _decimalsOffset() internal view override returns (uint8) {
        return decimalsOffset;
    }
}
