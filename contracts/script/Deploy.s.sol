// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Staking} from "../src/Staking.sol";

/// @notice Deploy with:
///   STAKING_TOKEN=0x... REWARDS_TOKEN=0x... forge script script/Deploy.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
/// Never commit a real private key. Use a dedicated testnet-only key.
contract Deploy is Script {
    function run() external {
        address stakingToken = vm.envAddress("STAKING_TOKEN");
        address rewardsToken = vm.envAddress("REWARDS_TOKEN");

        vm.startBroadcast();
        Staking staking = new Staking(stakingToken, rewardsToken);
        vm.stopBroadcast();

        console.log("Staking deployed at:", address(staking));
    }
}
