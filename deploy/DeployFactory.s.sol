// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {CampaignFactory} from "../contracts/CampaignFactory.sol";

/// @notice Deploys the CampaignFactory. Works against any RPC: Anvil locally (`make
///         deploy-local`), Ethereum Sepolia, or zkSync Sepolia with the right `--rpc-url`.
/// @dev CREATION_DEPOSIT (wei) is optional and defaults to 0.01 ether. The deployer key is the
///         broadcaster's; after deployment the deployer holds no ongoing power.
contract DeployFactory is Script {
    function run() external returns (address factory) {
        uint96 deposit = uint96(vm.envOr("CREATION_DEPOSIT", uint256(0.01 ether)));
        vm.startBroadcast();
        CampaignFactory f = new CampaignFactory(deposit);
        vm.stopBroadcast();
        factory = address(f);
        console2.log("CampaignFactory:", factory);
        console2.log("implementation: ", f.implementation());
        console2.log("creationDeposit:", f.creationDeposit());
    }
}
