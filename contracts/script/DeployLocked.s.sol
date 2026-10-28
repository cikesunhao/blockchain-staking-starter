// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {LockedStaking} from "../src/LockedStaking.sol";

/// @notice Deploy with:
///   TOKEN=0x... forge script script/DeployLocked.s.sol \
///     --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
/// Single token: users stake it and earn rewards in the same token.
/// Never commit a real private key. Use a dedicated testnet-only key.
contract DeployLocked is Script {
    function run() external {
        address tokenAddress = vm.envAddress("TOKEN");

        vm.startBroadcast();
        LockedStaking staking = new LockedStaking(tokenAddress);
        vm.stopBroadcast();

        console.log("LockedStaking deployed at:", address(staking));
    }
}
