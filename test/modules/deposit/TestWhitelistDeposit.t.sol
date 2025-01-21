// SPDX-License-Identifier: CC-BY-NC-4.0

pragma solidity ^0.8.0;

import {TestBaseDeposit, MINIMUM_DEPOSIT} from "./TestBaseDeposit.sol";
import {WhitelistDepositModule} from "@src/modules/deposit/WhitelistDepositModule.sol";
import {CreateAccountParams} from "@src/modules/deposit/Structs.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Errors} from "@src/libs/Errors.sol";

uint256 constant RELAYER_TIP = 10;
uint256 constant BRIBE = 10;

contract TestWhitelistDeposit is TestBaseDeposit {
    SafeL2 internal safe;
    WhitelistDepositModule internal whitelistDepositModule;
    uint256 internal accountId;

    function setUp() public override(TestBaseDeposit) {
        TestBaseDeposit.setUp();

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;
        safe = deploySafe(admins, 1);
        vm.label(address(safe), "Holding Safe");

        whitelistDepositModule = WhitelistDepositModule(
            deployModule(
                payable(address(safe)),
                fundAdmin,
                fundAdminPK,
                bytes32("whitelistDepositModule"),
                0,
                abi.encodePacked(
                    type(WhitelistDepositModule).creationCode,
                    abi.encode(address(fund), address(safe), address(periphery))
                )
            )
        );
        vm.label(address(whitelistDepositModule), "Whitelist Deposit Module");

        /// mint broker nft to safe, make unlimited
        vm.startPrank(address(fund));
        accountId = periphery.openAccount(
            CreateAccountParams({
                ttl: type(uint256).max - block.timestamp,
                shareMintLimit: type(uint256).max,
                brokerPerformanceFeeInBps: 0,
                protocolPerformanceFeeInBps: 0,
                brokerEntranceFeeInBps: 0,
                protocolEntranceFeeInBps: 0,
                brokerExitFeeInBps: 0,
                protocolExitFeeInBps: 0,
                feeRecipient: feeRecipient,
                user: address(safe),
                transferable: false
            })
        );
        vm.stopPrank();

        _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), true);
        _enableBrokerAssetPolicy(address(fund), 1, address(mockToken1), false);
    }

    modifier approveAllModule(address user) {
        vm.startPrank(user);
        mockToken1.approve(address(whitelistDepositModule), type(uint256).max);
        mockToken2.approve(address(whitelistDepositModule), type(uint256).max);
        periphery.internalVault().approve(address(whitelistDepositModule), type(uint256).max);
        vm.stopPrank();

        _;
    }

    function test_only_whitelisted_can_deposit_withdraw(
        uint128 _amount,
        bool intent,
        bool whitelisted
    ) public approveAllPeriphery(address(safe)) approveAllModule(alice) {
        vm.assume(_amount > MINIMUM_DEPOSIT);

        if (whitelisted) {
            vm.prank(address(safe));
            whitelistDepositModule.addUserToWhitelist(alice);
        }

        uint256 amount = uint256(_amount);
        mockToken1.mint(alice, amount);

        /// simple deposit on behalf of alice
        uint256 sharesOut;
        if (intent) {
            uint256 nonce = whitelistDepositModule.nonces(alice);

            vm.prank(relayer);
            if (!whitelisted) vm.expectRevert(Errors.OnlyWhitelisted.selector);
            sharesOut = whitelistDepositModule.intentDeposit(
                depositIntent(accountId, alice, alicePK, address(mockToken1), amount, 0, 0, nonce)
            );
        } else {
            vm.prank(alice);
            if (!whitelisted) vm.expectRevert(Errors.OnlyWhitelisted.selector);
            sharesOut = whitelistDepositModule.deposit(
                depositOrder(accountId, alice, address(mockToken1), amount)
            );
        }
    }

    function test_only_admin_can_add_remove_whitelisted_users(address attacker) public {
        vm.assume(attacker != address(safe));

        vm.expectRevert(Errors.OnlyAdmin.selector);
        vm.prank(attacker);
        whitelistDepositModule.addUserToWhitelist(alice);

        vm.expectRevert(Errors.OnlyAdmin.selector);
        vm.prank(attacker);
        whitelistDepositModule.removeUserFromWhitelist(alice);

        vm.prank(address(safe));
        whitelistDepositModule.addUserToWhitelist(alice);

        vm.prank(address(safe));
        whitelistDepositModule.removeUserFromWhitelist(alice);
    }
}
