// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

abstract contract TokenMinter is Test {
    // stablecoins deployed on arbitrum
    address constant ARB_USDCe = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
    address constant ARB_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
    address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant ARB_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;

    ERC20 public constant USDC = ERC20(ARB_USDC);
    ERC20 public constant USDT = ERC20(ARB_USDT);
    ERC20 public constant DAI = ERC20(ARB_DAI);
    ERC20 public constant USDCe = ERC20(ARB_USDCe);
    MockERC20 public MOCK_ERC20;

    // Gateway address
    address public constant USDCe_MINTER = 0x096760F208390250649E3e8763348E783AEF5562;
    // token minter
    address public constant USDC_MINTER = 0xE7Ed1fa7f45D05C508232aa32649D89b73b8bA48;
    // owner
    address public constant USDT_MINTER = 0x4a9196b06f339Ad9F3Ee752C987b401F2E1E2718;
    // ward
    address public constant DAI_MINTER = 0x467194771dAe2967Aef3ECbEDD3Bf9a310C76C65;

    function setUp() public virtual {
        MOCK_ERC20 = new MockERC20();

        // label tokens
        vm.label(address(USDC), "USDC");
        vm.label(address(USDT), "USDT");
        vm.label(address(DAI), "DAI");
        vm.label(address(USDCe), "USDCe");
        vm.label(address(MOCK_ERC20), "MOCK_ERC20");

        // label token minters
        vm.label(USDCe_MINTER, "USDCe_MINTER");
        vm.label(USDC_MINTER, "USDC_MINTER");
        vm.label(USDT_MINTER, "USDT_MINTER");
        vm.label(DAI_MINTER, "DAI_MINTER");
    }

    function mintUSDCe(address to, uint256 amount) public {
        bytes4 selector = bytes4(keccak256(bytes("bridgeMint(address,uint256)")));

        vm.prank(USDCe_MINTER);
        (bool success,) = address(USDCe).call(abi.encodeWithSelector(selector, to, amount));

        assertEq(success, true);
        assertEq(USDCe.balanceOf(to), amount);
    }

    function mintUSDC(address to, uint256 amount) public {
        bytes4 increaseSelector = bytes4(keccak256(bytes("configureMinter(address,uint256)")));

        address MASTER_MINTER = 0x8aFf09e2259cacbF4Fc4e3E53F3bf799EfEEab36;

        vm.prank(MASTER_MINTER);
        (bool success,) =
            address(USDC).call(abi.encodeWithSelector(increaseSelector, USDC_MINTER, amount));

        bytes4 selector = bytes4(keccak256(bytes("mint(address,uint256)")));

        vm.prank(USDC_MINTER);
        (success,) = address(USDC).call(abi.encodeWithSelector(selector, to, amount));

        assertEq(USDC.balanceOf(to), amount);
        assertEq(success, true);
    }

    function mintUSDT(address to, uint256 amount) public {
        bytes4 selector = bytes4(keccak256(bytes("mint(address,uint256)")));

        vm.prank(USDT_MINTER);
        (bool success,) = address(USDT).call(abi.encodeWithSelector(selector, to, amount));

        assertEq(USDT.balanceOf(to), amount);
        assertEq(success, true);
    }

    function mintDAI(address to, uint256 amount) public {
        bytes4 selector = bytes4(keccak256(bytes("mint(address,uint256)")));

        vm.prank(DAI_MINTER);
        (bool success,) = address(DAI).call(abi.encodeWithSelector(selector, to, amount));

        assertEq(DAI.balanceOf(to), amount);
        assertEq(success, true);
    }

    function mintMockERC20(address to, uint256 amount) public {
        MOCK_ERC20.mint(to, amount);
        assertEq(MOCK_ERC20.balanceOf(to), amount);
    }
}
