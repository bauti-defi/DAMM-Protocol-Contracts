// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

interface IProtocolAccessController {
    function isOwnerOrPauser(address _address) external view returns (bool);

    function setPauser(address _pauser) external;

    function removePauser(address _pauser) external;

    function isOwner(address _address) external view returns (bool);

    function isLocker(address _address) external view returns (bool);

    function setLocker(address _locker) external;
}
