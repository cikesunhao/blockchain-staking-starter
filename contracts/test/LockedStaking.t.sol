// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {LockedStaking} from "../src/LockedStaking.sol";

contract LockedMockToken is ERC20 {
    constructor() ERC20("Stake Token", "STK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LockedStakingTest is Test {
    LockedStaking public staking;
    LockedMockToken public token;
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);

    function setUp() public {
        token = new LockedMockToken();
        staking = new LockedStaking(address(token));

        token.mint(alice, 1_000 ether);
        token.mint(bob, 1_000 ether);
        token.mint(address(staking), 700 ether);

        vm.prank(alice);
        token.approve(address(staking), type(uint256).max);
        vm.prank(bob);
        token.approve(address(staking), type(uint256).max);
    }

    function testStakeSetsThirtyDayLock() public {
        vm.prank(alice);
        staking.stake(100 ether);
        assertEq(staking.lockEndOf(alice), block.timestamp + 30 days);
        assertTrue(staking.isLocked(alice));
    }

    function testWithdrawBeforeLockReverts() public {
        vm.prank(alice);
        staking.stake(100 ether);
        vm.prank(alice);
        vm.expectRevert("still locked, use earlyExit");
        staking.withdraw(100 ether);
    }

    function testAdditionalStakeResetsLock() public {
        vm.prank(alice);
        staking.stake(100 ether);
        vm.warp(block.timestamp + 20 days);
        vm.prank(alice);
        staking.stake(10 ether);
        assertEq(staking.lockEndOf(alice), block.timestamp + 30 days);
    }

    function testEarlyExitPenaltyGoesToRemainingStaker() public {
        vm.prank(alice);
        staking.stake(100 ether);
        vm.prank(bob);
        staking.stake(100 ether);

        // 700 over 7 days = 100/day, split 50/50 between alice and bob.
        staking.notifyRewardAmount(700 ether);
        vm.warp(block.timestamp + 1 days);

        // Alice exits early: 5 penalty + 50 forfeited rewards = 55
        // redistributed to bob, the sole remaining staker.
        vm.prank(alice);
        staking.earlyExit(100 ether);

        assertEq(token.balanceOf(alice), 995 ether); // 1000 - 100 + 95
        assertEq(staking.earned(alice), 0);
        // 50 normal + 55 redistributed. Approx, not exact: rewardRate is
        // 700 ether / 7 days in whole seconds, so integer division leaves
        // a few hundred wei of dust. That dust is a real interview point.
        assertApproxEqAbs(staking.earned(bob), 105 ether, 1_000_000);
        assertEq(staking.balanceOf(bob), 100 ether);
    }

    function testNormalWithdrawAfterLock() public {
        vm.prank(alice);
        staking.stake(100 ether);
        staking.notifyRewardAmount(700 ether);
        vm.warp(block.timestamp + 31 days);

        vm.prank(alice);
        staking.withdraw(100 ether);
        vm.prank(alice);
        staking.getReward();

        // Principal back (1000) plus full 7-day rewards (700),
        // because alice was the only staker. Approx for the same
        // integer-division dust as above.
        assertApproxEqAbs(token.balanceOf(alice), 1_700 ether, 1_000_000);
    }

    function testEarlyExitAfterLockReverts() public {
        vm.prank(alice);
        staking.stake(100 ether);
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        vm.expectRevert("lock expired, use withdraw");
        staking.earlyExit(100 ether);
    }
}
