// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {VerdictToken} from "../src/VerdictToken.sol";

/// @title Deploy script for VerdictToken
/// @notice The launch itself deploys the token from its built bytecode through the project factory;
///         this script exists for reviewers and for manual deployments to a fork or test network.
///         The token has no constructor arguments and no post-deployment configuration, so there is
///         nothing to read from the environment: `run()` only broadcasts `deploy()`.
contract DeployVerdictToken is Script {
    /// @notice Deploys the token. The caller of this function (the broadcasting account when run
    ///         through `forge script`, the test contract when called from a test) receives the
    ///         whole supply, because the token mints to `msg.sender`.
    function deploy() public returns (VerdictToken token) {
        token = new VerdictToken();
    }

    /// @notice Entry point for `forge script`. Broadcasts the deployment from the configured sender.
    function run() external returns (VerdictToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
