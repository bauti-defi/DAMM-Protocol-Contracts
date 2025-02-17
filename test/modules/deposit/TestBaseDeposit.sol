// SPDX-License-Identifier: CC-BY-NC-4.0
pragma solidity ^0.8.0;

import {TestBaseGnosis} from "@test/base/TestBaseGnosis.sol";
import {EulerRouter} from "@euler-price-oracle/EulerRouter.sol";
import {ISafe} from "@src/interfaces/ISafe.sol";
import {Periphery} from "@src/modules/deposit/Periphery.sol";
import {BalanceOfOracle} from "@src/oracles/BalanceOfOracle.sol";
import {MockERC20} from "@test/mocks/MockERC20.sol";
import {MockPriceOracle} from "@test/mocks/MockPriceOracle.sol";
import {SignedMath} from "@openzeppelin-contracts/utils/math/SignedMath.sol";
import {MessageHashUtils} from "@openzeppelin-contracts/utils/cryptography/MessageHashUtils.sol";
import {console2} from "@forge-std/Test.sol";
import "@src/libs/Constants.sol";
import "@src/modules/deposit/Structs.sol";
import {ModuleProxyFactory} from "@zodiac/factory/ModuleProxyFactory.sol";
import "@src/modules/deposit/DepositModule.sol";
import {IERC20} from "@openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin-contracts/interfaces/IERC4626.sol";

uint8 constant VALUATION_DECIMALS = 18;
uint256 constant VAULT_DECIMAL_OFFSET = 1;
uint256 constant MINIMUM_DEPOSIT = 1000;
uint256 constant MINIMUM_WITHDRAWAL = 1000;

abstract contract TestBaseDeposit is TestBaseGnosis {
    using MessageHashUtils for bytes;
    using SignedMath for int256;

    address internal fundAdmin;
    uint256 internal fundAdminPK;
    ISafe internal fund;
    EulerRouter internal oracleRouter;
    DepositModule internal depositModule;
    address internal depositModuleMastercopy;
    MockERC20 internal mockToken1;
    MockERC20 internal mockToken2;

    IERC4626 internal internalVault;

    BalanceOfOracle internal balanceOfOracle;

    address alice;
    uint256 internal alicePK;
    address bob;
    uint256 internal bobPK;

    uint256 mock1Unit;
    uint256 mock2Unit;
    uint256 oneUnitOfAccount;

    uint256 internal precisionLoss;

    function setUp() public virtual override(TestBaseGnosis) {
        TestBaseGnosis.setUp();

        (alice, alicePK) = makeAddrAndKey("Alice");

        (bob, bobPK) = makeAddrAndKey("Bob");

        (fundAdmin, fundAdminPK) = makeAddrAndKey("FundAdmin");
        vm.deal(fundAdmin, 1000 ether);

        address[] memory admins = new address[](1);
        admins[0] = fundAdmin;

        fund = ISafe(address(deploySafe(admins, 1, 1)));
        vm.label(address(fund), "Fund");

        require(address(fund).balance == 0, "Fund should not have balance");

        assertTrue(address(fund) != address(0), "Failed to deploy fund");
        assertTrue(fund.isOwner(fundAdmin), "Fund admin not owner");

        vm.prank(address(fund));
        oracleRouter = new EulerRouter(address(1), address(fund));
        vm.label(address(oracleRouter), "OracleRouter");

        mockToken1 = new MockERC20(VALUATION_DECIMALS);
        vm.label(address(mockToken1), "MockToken1");

        mockToken2 = new MockERC20(VALUATION_DECIMALS);
        vm.label(address(mockToken2), "MockToken2");

        mock1Unit = 1 * 10 ** mockToken1.decimals();
        mock2Unit = 1 * 10 ** mockToken2.decimals();

        ModuleProxyFactory factory = new ModuleProxyFactory();

        depositModuleMastercopy = address(new DepositModule());

        bytes memory depositModuleInitializer = abi.encodeWithSelector(
            DepositModule.setUp.selector,
            abi.encode(
                "DepositModule", "DM", VALUATION_DECIMALS, 0, address(fund), address(oracleRouter)
            )
        );

        depositModule = DepositModule(
            factory.deployModule(
                depositModuleMastercopy,
                depositModuleInitializer,
                uint256(bytes32("depositModule-salt"))
            )
        );

        vm.label(address(depositModule), "DepositModule");

        vm.startPrank(address(fund));
        fund.enableModule(address(depositModule));
        vm.stopPrank();

        assertTrue(fund.isModuleEnabled(address(depositModule)), "DepositModule not module");

        internalVault = IERC4626(address(depositModule.internalVault()));

        uint8 unitOfAccountDecimals = depositModule.unitOfAccount().decimals();

        precisionLoss = 10 ** (VALUATION_DECIMALS - unitOfAccountDecimals);

        /// @notice this much match the vault implementation
        oneUnitOfAccount = 1 * 10 ** unitOfAccountDecimals;

        // lets enable assets on the fund
        vm.startPrank(address(fund));
        depositModule.enableGlobalAssetPolicy(
            address(mockToken1),
            AssetPolicy({
                minimumDeposit: 50 * mock1Unit,
                minimumWithdrawal: 1 * mock1Unit,
                canDeposit: true,
                canWithdraw: true,
                enabled: true
            })
        );

        depositModule.enableGlobalAssetPolicy(
            address(mockToken2),
            AssetPolicy({
                minimumDeposit: 50 * mock2Unit,
                minimumWithdrawal: 1 * mock2Unit,
                canDeposit: true,
                canWithdraw: true,
                enabled: true
            })
        );
        vm.stopPrank();

        address unitOfAccount = address(depositModule.unitOfAccount());

        balanceOfOracle = new BalanceOfOracle(address(fund), address(oracleRouter));
        vm.label(address(balanceOfOracle), "BalanceOfOracle");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(fund), unitOfAccount, address(balanceOfOracle));

        MockPriceOracle mockPriceOracle = new MockPriceOracle(
            address(mockToken1), unitOfAccount, oneUnitOfAccount, VALUATION_DECIMALS
        );
        vm.label(address(mockPriceOracle), "MockPriceOracle1");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(mockToken1), unitOfAccount, address(mockPriceOracle));

        mockPriceOracle = new MockPriceOracle(
            address(mockToken2), unitOfAccount, 2 * oneUnitOfAccount, VALUATION_DECIMALS
        );
        vm.label(address(mockPriceOracle), "MockPriceOracle2");
        vm.prank(address(fund));
        oracleRouter.govSetConfig(address(mockToken2), unitOfAccount, address(mockPriceOracle));

        vm.startPrank(address(fund));
        oracleRouter.govSetResolvedVault(depositModule.getVault(), true);
        vm.stopPrank();
    }

    modifier withRole(address user, bytes32 role) {
        vm.startPrank(address(fund));
        depositModule.grantRole(role, user);
        vm.stopPrank();
        _;
    }

    modifier maxApproveDepositModule(address user, address token) {
        vm.startPrank(user);
        IERC20(token).approve(address(depositModule), type(uint256).max);
        vm.stopPrank();
        _;
    }
}
