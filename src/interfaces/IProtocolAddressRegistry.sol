// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

interface IProtocolAddressRegistry {
    event AddressSet(bytes32 indexed identifier, address indexed newAddress, address indexed oldAddress);

    function getAddress(bytes32 identifier) external view returns (address);

    function setAddress(bytes32 identifier, address _address) external;

    function getAccessController() external view returns (address);

    function setAccessController(address _address) external;

    function getVaultFactory() external view returns (address);

    function setVaultFactory(address _address) external;

    function getDAMMGnosisModule() external view returns (address);

    function setDAMMGnosisModule(address _address) external;

    function getVaultGuard() external view returns (address);

    function setVaultGuard(address _address) external;

    function getProtocolState() external view returns (address);

    function setProtocolState(address _address) external;

    function getRouterWhitelistRegistry() external view returns (address);

    function setRouterWhitelistRegistry(address _address) external;

    function getTokenWhitelistRegistry() external view returns (address);

    function setTokenWhitelistRegistry(address _address) external;

    function getMulticallerWithSender() external view returns (address);

    function setMulticallerWithSender(address _address) external;

    function isRegistered(address _address) external view returns (bool);
}
