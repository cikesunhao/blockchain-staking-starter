// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Staking} from "../src/Staking.sol";

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract StakingTest is Test {
    Staking public staking;
    MockToken public stakeToken;
    MockToken public rewardToken;
    address public alice = address(0xA11CE);

    function setUp() public {
        stakeToken = new MockToken("Stake Token", "STK");
        rewardToken = new MockToken("Reward Token", "RWD");
        staking = new Staking(address(stakeToken), address(rewardToken));

        stakeToken.mint(alice, 1_000 ether);
        rewardToken.mint(address(staking), 700 ether);

        vm.prank(alice);
        stakeToken.approve(address(staking), type(uint256).max);
    }

    function testStakeAndEarn() public {
        vm.prank(alice);
        staking.stake(100 ether);

        staking.notifyRewardAmount(700 ether);

        vm.warp(block.timestamp + 1 days);
        assertGt(staking.earned(alice), 0, "should have earned after 1 day");

        vm.prank(alice);
        staking.getReward();
        assertGt(rewardToken.balanceOf(alice), 0, "should have received rewards");
    }

    function testWithdrawReturnsStake() public {
        vm.prank(alice);
        staking.stake(100 ether);

        vm.prank(alice);
        staking.withdraw(40 ether);

        assertEq(stakeToken.balanceOf(alice), 940 ether);
        assertEq(staking.balanceOf(alice), 60 ether);
    }

    function testCannotStakeZero() public {
        vm.prank(alice);
        vm.expectRevert("cannot stake 0");
        staking.stake(0);
    }
}
