// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin-contracts/token/ERC20/extensions/ERC4626.sol";

interface IPeriphery {
    function totalAssets() external view returns (uint256);
}

contract FundShareVault is ERC4626 {
    IPeriphery internal immutable periphery;

    constructor(address _periphery, string memory _name, string memory _symbol)
        ERC4626(IERC20(_periphery))
        ERC20(_name, _symbol)
    {
        periphery = IPeriphery(_periphery);
    }

    modifier onlyPeriphery() {
        require(msg.sender == address(periphery), "ONLY_PERIPHERY");
        _;
    }

    function totalAssets() public view override returns (uint256) {
        return periphery.totalAssets();
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
        return 2;
    }

    /// @dev do not allow transfers
    function transfer(address, uint256) public pure override(ERC20, IERC20) returns (bool) {
        return false;
    }

    /// @dev do not allow transfers
    function transferFrom(address, address, uint256)
        public
        pure
        override(ERC20, IERC20)
        returns (bool)
    {
        return false;
    }
}
