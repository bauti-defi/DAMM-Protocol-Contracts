// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBaseDeposit, MINIMUM_DEPOSIT} from "./TestBaseDeposit.sol";
import {
    WhitelistDepositModule,
    DepositModule,
    WHITELIST_ROLE,
    USER_ROLE,
    IAccessControl
} from "@src/modules/deposit/WhitelistDepositModule.sol";
import {CreateAccountParams} from "@src/modules/deposit/Structs.sol";
import {SafeL2} from "@safe-contracts/SafeL2.sol";
import {Errors} from "@src/libs/Errors.sol";
import {ModuleProxyFactory} from "@zodiac/factory/ModuleProxyFactory.sol";

uint256 constant RELAYER_TIP = 10;
uint256 constant BRIBE = 10;

contract TestWhitelistDeposit is TestBaseDeposit {
    SafeL2 internal safe;
    address internal moduleMasterCopy;
    WhitelistDepositModule internal whitelistDepositModule;
    uint256 internal accountId;

    function setUp() public override(TestBaseDeposit) {
        TestBaseDeposit.setUp();

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;
        safe = deploySafe(admins, 1, 2);
        vm.label(address(safe), "Holding Safe");

        ModuleProxyFactory factory = new ModuleProxyFactory();

        moduleMasterCopy = address(new WhitelistDepositModule());

        bytes memory initializer = abi.encodeWithSelector(
            DepositModule.setUp.selector,
            abi.encode(address(fund), address(safe), address(periphery))
        );

        whitelistDepositModule = WhitelistDepositModule(
            factory.deployModule(
                moduleMasterCopy, initializer, uint256(bytes32("whitelist-module-salt"))
            )
        );
        vm.label(address(whitelistDepositModule), "Whitelist Deposit Module");

        vm.startPrank(address(safe));
        safe.enableModule(address(whitelistDepositModule));
        vm.stopPrank();

        assertTrue(safe.isModuleEnabled(address(whitelistDepositModule)), "Module not enabled");
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

        vm.startPrank(address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken1), address(fund));
        balanceOfOracle.addBalanceToValuate(address(mockToken2), address(fund));
        vm.stopPrank();
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
            vm.prank(address(fund));
            whitelistDepositModule.grantRole(USER_ROLE, alice);
        }

        uint256 amount = uint256(_amount);
        mockToken1.mint(alice, amount);

        /// simple deposit on behalf of alice
        uint256 sharesOut;
        if (intent) {
            uint256 nonce = whitelistDepositModule.nonces(alice);

            vm.prank(relayer);
            if (!whitelisted) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IAccessControl.AccessControlUnauthorizedAccount.selector, alice, USER_ROLE
                    )
                );
            }
            sharesOut = whitelistDepositModule.intentDeposit(
                depositIntent(accountId, alice, alicePK, address(mockToken1), amount, 0, 0, nonce)
            );
        } else {
            vm.prank(alice);
            if (!whitelisted) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        IAccessControl.AccessControlUnauthorizedAccount.selector, alice, USER_ROLE
                    )
                );
            }
            sharesOut = whitelistDepositModule.deposit(
                depositOrder(accountId, alice, address(mockToken1), amount)
            );
        }
    }
}
