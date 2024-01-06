// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.18;

import {Pausable} from "@openzeppelin-contracts/utils/Pausable.sol";
import {IProtocolAddressRegistry} from "@src/interfaces/IProtocolAddressRegistry.sol";
import {IProtocolAccessController} from "@src/interfaces/IProtocolAccessController.sol";
import "@src/interfaces/IProtocolState.sol";
import {SafeGet} from "@src/lib/SafeGet.sol";

contract ProtocolState is Pausable, IProtocolState {
    using SafeGet for address;

    IProtocolAddressRegistry private immutable ADDRESS_REGISTRY;

    constructor(IProtocolAddressRegistry addressRegistry) {
        ADDRESS_REGISTRY = addressRegistry;
    }

    function accessController() private view returns (IProtocolAccessController) {
        return IProtocolAccessController(ADDRESS_REGISTRY.getAccessController().orRevert());
    }

    function pause() external override {
        require(accessController().isOwnerOrPauser(msg.sender), "ProtocolState: permission denied");
        _pause();
    }

    function paused() public view override(IPausable, Pausable) returns (bool) {
        return super.paused();
    }

    function unpause() external override {
        require(accessController().isOwner(msg.sender), "ProtocolState: permission denied");
        _unpause();
    }

    function requireNotStopped() external view override {
        require(!paused(), "ProtocolState: stopped");
    }
}
