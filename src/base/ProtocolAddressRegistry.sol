// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {IProtocolAccessController} from "@src/interfaces/IProtocolAccessController.sol";

contract ProtocolAddressRegistry is IProtocolAddressRegistry {
    bytes32 private constant VAULT_FACTORY = keccak256("VAULT_FACTORY");
    bytes32 private constant DAMM_GNOSIS_MODULE = keccak256("DAMM_GNOSIS_MODULE");
    bytes32 private constant VAULT_GUARD = keccak256("VAULT_GUARD");
    bytes32 private constant PROTOCOL_STATE = keccak256("PROTOCOL_STATE");
    bytes32 private constant ROUTER_WHITELIST_REGISTRY = keccak256("ROUTER_WHITELIST_REGISTRY");
    bytes32 private constant TOKEN_WHITELIST_REGISTRY = keccak256("TOKEN_WHITELIST_REGISTRY");
    bytes32 private constant ACCESS_CONTROLLER = keccak256("ACCESS_CONTROLLER");
    bytes32 private constant MULTICALLER_WITH_SENDER = keccak256("MULTICALLER_WITH_SENDER");

    mapping(bytes32 identifier => address) private _addresses;
    mapping(address => bytes32 identifier) private _identifiers;

    constructor(address _protocolAccessController) {
        require(
            _protocolAccessController != address(0),
            "ProtocolAddressRegistry: Invalid access controller"
        );
        require(
            IProtocolAccessController(_protocolAccessController).isOwner(msg.sender),
            "ProtocolAddressRegistry: Caller is not the owner"
        );

        _addresses[ACCESS_CONTROLLER] = _protocolAccessController;
        _identifiers[_protocolAccessController] = ACCESS_CONTROLLER;
        emit AddressSet(ACCESS_CONTROLLER, _protocolAccessController, address(0));
    }

    function _getAddress(bytes32 identifier) private view returns (address) {
        return _addresses[identifier];
    }

    function getAddress(bytes32 identifier) external view override returns (address) {
        return _getAddress(identifier);
    }

    function _setAddress(bytes32 identifier, address _address) private {
        require(
            IProtocolAccessController(_getAddress(ACCESS_CONTROLLER)).isOwner(msg.sender),
            "ProtocolAddressRegistry: Caller is not the owner"
        );

        address oldAddress = _addresses[identifier];
        _addresses[identifier] = _address;
        _identifiers[_address] = identifier;
        delete _identifiers[oldAddress];

        emit AddressSet(identifier, _address, oldAddress);
    }

    function setAddress(bytes32 identifier, address _address) external override {
        _setAddress(identifier, _address);
    }

    function getAccessController() external view override returns (address) {
        return _getAddress(ACCESS_CONTROLLER);
    }

    function setAccessController(address _address) external override {
        _setAddress(ACCESS_CONTROLLER, _address);
    }

    function getVaultFactory() external view override returns (address) {
        return _getAddress(VAULT_FACTORY);
    }

    function setVaultFactory(address _address) external override {
        _setAddress(VAULT_FACTORY, _address);
    }

    function getDAMMGnosisModule() external view override returns (address) {
        return _getAddress(DAMM_GNOSIS_MODULE);
    }

    function setDAMMGnosisModule(address _address) external override {
        _setAddress(DAMM_GNOSIS_MODULE, _address);
    }

    function getVaultGuard() external view override returns (address) {
        return _getAddress(VAULT_GUARD);
    }

    function setVaultGuard(address _address) external override {
        _setAddress(VAULT_GUARD, _address);
    }

    function getProtocolState() external view override returns (address) {
        return _getAddress(PROTOCOL_STATE);
    }

    function setProtocolState(address _address) external override {
        _setAddress(PROTOCOL_STATE, _address);
    }

    function getRouterWhitelistRegistry() external view override returns (address) {
        return _getAddress(ROUTER_WHITELIST_REGISTRY);
    }

    function setRouterWhitelistRegistry(address _address) external override {
        _setAddress(ROUTER_WHITELIST_REGISTRY, _address);
    }

    function getTokenWhitelistRegistry() external view override returns (address) {
        return _getAddress(TOKEN_WHITELIST_REGISTRY);
    }

    function setTokenWhitelistRegistry(address _address) external override {
        _setAddress(TOKEN_WHITELIST_REGISTRY, _address);
    }

    function getMulticallerWithSender() external view override returns (address) {
        return _getAddress(MULTICALLER_WITH_SENDER);
    }

    function setMulticallerWithSender(address _address) external override {
        _setAddress(MULTICALLER_WITH_SENDER, _address);
    }

    function isRegistered(address _address) external view override returns (bool) {
        return _address == address(this) || _identifiers[_address] != bytes32(0);
    }
}
