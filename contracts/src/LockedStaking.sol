// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LockedStaking
/// @notice Single-token staking with a 30-day lock, built on the plain
/// Staking skeleton in this repo. Rewards and penalties are in the same
/// token, which is what makes the redistribution below accounting-clean.
///
/// @dev Design decisions, stated so they can be defended in an interview:
///  - Every stake resets the user's lock to now + 30 days. This is simple
///    and stops reward farming by re-staking, but it re-locks old funds too.
///    A production version could track per-stake positions instead.
///  - Normal withdraw is blocked while locked; early exit is a separate,
///    explicit function, so the penalty is never a surprise.
///  - Early exit forfeits ALL pending rewards for that user (not just a
///    pro-rata share) and takes a 5% principal penalty. Both amounts are
///    redistributed to remaining stakers immediately by raising
///    rewardPerTokenStored: rewardPerTokenStored += redistributed * 1e18
///    / remainingTotalSupply. This is O(1) -- no loop over users.
///  - If nobody remains (the exiting user was the sole staker), the amount
///    goes into undistributedPool and is folded into the next reward
///    period by notifyRewardAmount, instead of being sent to the owner.
///  - This is a learning skeleton, NOT audited. Testnet only.
contract LockedStaking is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    uint256 public constant LOCK_DURATION = 30 days;
    uint256 public constant PENALTY_BPS = 500; // 5%
    uint256 public constant BPS_DENOMINATOR = 10_000;

    uint256 public periodFinish;
    uint256 public rewardRate;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public undistributedPool;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;
    mapping(address => uint256) public lockEnd;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    event Staked(address indexed user, uint256 amount, uint256 lockEnd);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event EarlyExit(address indexed user, uint256 amount, uint256 penalty, uint256 forfeitedReward);

    constructor(address _token) Ownable(msg.sender) {
        require(_token != address(0), "zero address");
        token = IERC20(_token);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lockEndOf(address account) external view returns (uint256) {
        return lockEnd[account];
    }

    function isLocked(address account) public view returns (bool) {
        return block.timestamp < lockEnd[account];
    }

    function penaltyFor(uint256 amount) public pure returns (uint256) {
        return (amount * PENALTY_BPS) / BPS_DENOMINATOR;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored
            + ((lastTimeRewardApplicable() - lastUpdateTime) * rewardRate * 1e18) / _totalSupply;
    }

    function earned(address account) public view returns (uint256) {
        return ((_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18)
            + rewards[account];
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "cannot stake 0");
        _totalSupply += amount;
        _balances[msg.sender] += amount;
        // Documented trade-off: any new stake restarts the 30-day lock.
        lockEnd[msg.sender] = block.timestamp + LOCK_DURATION;
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount, lockEnd[msg.sender]);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(!isLocked(msg.sender), "still locked, use earlyExit");
        require(amount > 0, "cannot withdraw 0");
        require(_balances[msg.sender] >= amount, "insufficient balance");
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        token.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            token.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Exit while locked. Forfeits all pending rewards and pays a
    /// 5% principal penalty; both are redistributed to remaining stakers
    /// (or parked in undistributedPool if nobody remains).
    function earlyExit(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(isLocked(msg.sender), "lock expired, use withdraw");
        require(amount > 0, "cannot exit 0");
        require(_balances[msg.sender] >= amount, "insufficient balance");

        uint256 forfeited = rewards[msg.sender];
        rewards[msg.sender] = 0;
        uint256 penalty = penaltyFor(amount);

        _totalSupply -= amount;
        _balances[msg.sender] -= amount;

        uint256 redistributed = forfeited + penalty;
        if (_totalSupply > 0) {
            rewardPerTokenStored += (redistributed * 1e18) / _totalSupply;
        } else {
            undistributedPool += redistributed;
        }

        token.safeTransfer(msg.sender, amount - penalty);
        emit EarlyExit(msg.sender, amount, penalty, forfeited);
    }

    /// @notice Fund a new reward period. Reward tokens must already be in
    /// this contract (owner transfers them first). Any undistributed
    /// penalty/forfeited amount is folded into this period's rate.
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        uint256 totalReward = reward + undistributedPool;
        undistributedPool = 0;
        if (block.timestamp >= periodFinish) {
            rewardRate = totalReward / rewardsDuration;
        } else {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            rewardRate = (totalReward + leftover) / rewardsDuration;
        }
        uint256 balance = token.balanceOf(address(this));
        require(rewardRate <= balance / rewardsDuration, "reward too high");
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + rewardsDuration;
        emit RewardAdded(reward);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(block.timestamp > periodFinish, "period not finished");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(_rewardsDuration);
    }
}
