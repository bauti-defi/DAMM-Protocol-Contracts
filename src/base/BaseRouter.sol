// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.23;

import {IRouter} from "@src/interfaces/IRouter.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@src/lib/ReentrancyGuard.sol";
import {IMulticall} from "@src/interfaces/IMulticall.sol";
import {ITokenWhitelistRegistry} from "@src/interfaces/ITokenWhitelistRegistry.sol";

abstract contract BaseRouter is IRouter, IMulticall, ReentrancyGuard {
    modifier setCaller() {
        if (caller == address(0)) caller = msg.sender;
        _;
        caller = address(0);
    }

    address internal caller;

    ITokenWhitelistRegistry public immutable tokenWhitelistRegistry;
    address public immutable owner;

    constructor(address _owner, address _tokenWhitelistRegistry) {
        owner = _owner;
        tokenWhitelistRegistry = ITokenWhitelistRegistry(_tokenWhitelistRegistry);
    }

    /// @notice This implementation is from Uniswap's V3 Periphery: https://github.com/Uniswap/v3-periphery/blob/main/contracts/base/Multicall.sol
    /// @notice All functions in `data` must be payable
    function multicall(bytes[] calldata data) external payable override nonReentrant returns (bytes[] memory results) {
        results = new bytes[](data.length);
        for (uint256 i = 0; i < data.length; i++) {
            (bool success, bytes memory result) = address(this).delegatecall(data[i]);

            if (!success) {
                // Next 5 lines from https://ethereum.stackexchange.com/a/83577
                if (result.length < 68) revert();
                assembly {
                    result := add(result, 0x04)
                }
                revert(abi.decode(result, (string)));
            }

            results[i] = result;
        }
    }

    function isTokenWhitelisted(address user, address token) public view returns (bool) {
        return tokenWhitelistRegistry.isTokenWhitelisted(user, address(this), token);
    }

    function _checkTokenIsWhitelisted(address user, address token) internal view {
        if (!isTokenWhitelisted(user, token)) revert TokenNotWhitelisted();
    }

    fallback() external payable {
        revert("Router: invalid fallback");
    }

    // @notice To receive ETH from WETH and NFT protocols
    receive() external payable {}
}
