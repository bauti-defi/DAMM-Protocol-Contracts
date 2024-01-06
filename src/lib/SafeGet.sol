// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

library SafeGet {
    error UnsafeGet(string reason);

    function orRevert(address self) external pure returns (address) {
        if (self == address(0)) {
            revert UnsafeGet("zero address");
        }

        return self;
    }
}
