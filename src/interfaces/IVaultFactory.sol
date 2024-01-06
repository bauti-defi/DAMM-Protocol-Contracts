// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IVaultFactory {
    event VaultDeployed(
        address indexed vault, address[] owners, address vaultGuard, address tradingModule, uint256 nonce
    );

    function vaultDeploymentCallback(address _tradingModule, address _vaultGuard) external;

    function deployDAMMVault(address[] memory _owners, uint256 _threshold) external returns (address);

    function getDeployedVaultNonce(address _vault) external view returns (uint256);
}
