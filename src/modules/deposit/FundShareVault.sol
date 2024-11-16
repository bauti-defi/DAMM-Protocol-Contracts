// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";
import "@src/libs/Errors.sol";

contract FundShareVault is ERC4626 {
    address internal immutable periphery;

    constructor(address _unitOfAccount, string memory _name, string memory _symbol)
        ERC4626(IERC20(_unitOfAccount))
        ERC20(_name, _symbol)
    {
        periphery = msg.sender;
    }

    modifier onlyPeriphery() {
        if (msg.sender != address(periphery)) revert Errors.Deposit_OnlyPeriphery();
        _;
    }

    function deposit(uint256 assets, address receiver)
        public
        override
        onlyPeriphery
        returns (uint256 shares)
    {
        shares = super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver)
        public
        override
        onlyPeriphery
        returns (uint256 assets)
    {
        assets = super.mint(shares, receiver);
    }

    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        onlyPeriphery
        returns (uint256 assets)
    {
        assets = super.redeem(shares, receiver, owner);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        onlyPeriphery
        returns (uint256 shares)
    {
        shares = super.withdraw(assets, receiver, owner);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 1;
    }
}
