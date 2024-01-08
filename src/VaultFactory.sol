// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {IVaultFactory} from "@src/interfaces/IVaultFactory.sol";
import {ISafe} from "@src/interfaces/external/ISafe.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {IProtocolState} from "@src/interfaces/IProtocolState.sol";

import "@safe-contracts/proxies/SafeProxyFactory.sol";
import {SafeGet} from "@src/lib/SafeGet.sol";

contract VaultFactory is IVaultFactory {
    using SafeGet for address;

    IProtocolAddressRegistry private immutable ADDRESS_REGISTRY;

    address public immutable safeFactory;
    address public immutable tokenCallbackHandler;
    address public immutable singleton;

    uint256 public nonce;

    mapping(address vault => uint256 nonce) public deployedVaults;

    constructor(
        IProtocolAddressRegistry _addressRegsitry,
        address _safeFactory,
        address _tokenCallbackHandler,
        address _singleton
    ) {
        ADDRESS_REGISTRY = _addressRegsitry;
        safeFactory = _safeFactory;
        tokenCallbackHandler = _tokenCallbackHandler;
        singleton = _singleton;
        nonce = 0;
    }

    function deployDAMMVault(address[] memory owners, uint256 threshold)
        public
        returns (address vault)
    {
        IProtocolState(ADDRESS_REGISTRY.getProtocolState().orRevert()).requireNotStopped();

        require(threshold > 0 && threshold <= owners.length, "VaultFactory: Invalid threshold");

        address tradingModule = ADDRESS_REGISTRY.getDAMMGnosisModule().orRevert();
        address vaultGuard = ADDRESS_REGISTRY.getVaultGuard().orRevert();

        // Delegate call from the vault so that the trading module module can be enabled right after the vault is deployed
        // and the guard is set.
        bytes memory data =
            abi.encodeCall(VaultFactory.vaultDeploymentCallback, (tradingModule, vaultGuard));

        // create gnosis safe initializer payload
        bytes memory initializerPayload = abi.encodeCall(
            ISafe.setup,
            (
                owners, // owners
                threshold, // multisig signer threshold
                address(this), // to
                data, // data
                tokenCallbackHandler, // fallback manager
                address(0), // payment token
                0, // payment amount
                payable(address(0)) // payment receiver
            )
        );

        // deploy a safe proxy using initializer values for the Safe.setup() call
        // with a salt nonce that is unique to each chain to guarantee cross-chain unique safe addresses
        vault = address(
            SafeProxyFactory(safeFactory).createProxyWithNonce(
                singleton,
                initializerPayload,
                uint256(keccak256(abi.encode(++nonce, block.chainid)))
            )
        );

        // register the vault with the factory
        deployedVaults[vault] = nonce;

        emit VaultDeployed(vault, owners, vaultGuard, tradingModule, nonce);
    }

    // INVARIANT: This function assumes the invariant that delegate call will be disabled on safe contracts
    // via the vault guard. If delegate call were to be allowed, then a safe could call this function after
    // deployment and change the module/guard contracts which would allow transfering of tokens out of the vault
    function vaultDeploymentCallback(address _tradingModule, address _vaultGuard) external {
        ISafe(address(this)).enableModule(_tradingModule);

        ISafe(address(this)).setGuard(_vaultGuard);
    }

    function getDeployedVaultNonce(address vault) public view returns (uint256) {
        return deployedVaults[vault];
    }

    function isDAMMVault(address vault) public view override returns (bool) {
        return deployedVaults[vault] != 0;
    }
}
