// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {Counter} from "../src/Counter.sol";

/// @title DeployCounter
/// @notice Reviewable deployment logic for `Counter`. The IdentityMD launch deploys the contract from
///         its built bytecode through the project factory; this script exists so the exact deployment
///         can be rehearsed locally and tested directly. It reads no environment variables.
/// @dev `Counter` takes no constructor arguments, so there is nothing to configure here.
contract DeployCounter is Script {
    /// @notice Deploys a fresh `Counter`. Tests call this directly.
    /// @return counter The deployed instance.
    function deploy() public returns (Counter counter) {
        counter = new Counter();
    }

    /// @notice Entry point for `forge script`. Broadcasting is the caller's decision via `--broadcast`;
    ///         this task does not broadcast anything.
    function run() external returns (Counter counter) {
        vm.startBroadcast();
        counter = deploy();
        vm.stopBroadcast();
    }
}
