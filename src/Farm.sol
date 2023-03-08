pragma solidity ^0.8.14;

import {GemAbstract} from "dss-interfaces/ERC/GemAbstract.sol";
import {SafeMath} from "./utils/SafeMath.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

contract Farm is ReentrancyGuard {
    using SafeMath for uint256;

    GemAbstract public immutable rewardGem;
    GemAbstract public immutable gem;

    // @notice Addresses with admin access on this contract. `wards[usr]`.
    mapping(address => uint256) public wards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint public lastPauseTime;
    bool public paused;
    address public rewardsDistribution;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /**
     * @notice `usr` was granted admin access.
     * @param usr The user address.
     */
    event Rely(address indexed usr);

    /**
     * @notice `usr` admin access was revoked.
     * @param usr The user address.
     */
    event Deny(address indexed usr);
    event PauseChanged(bool isPaused);
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amt, address to);

    /**
     * @notice Only addresses with admin access can call methods with this modifier.
     */
    modifier auth() {
        require(wards[msg.sender] == 1, "Farm/not-authorized");
        _;
    }

    modifier notPaused() {
        require(!paused, "Farm/is-paused");
        _;
    }

    modifier onlyRewardsDistribution() {
        require(msg.sender == rewardsDistribution, "Farm/not-rewards-distribution");
        _;
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

    constructor(address _rewardsDistribution, address _rewardGem, address _gem) public {
        rewardGem = GemAbstract(_rewardGem);
        gem = GemAbstract(_gem);
        rewardsDistribution = _rewardsDistribution;

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /**
     * @notice Grants `usr` admin access to this contract.
     * @param usr The user address.
     */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
     * @notice Revokes `usr` admin access from this contract.
     * @param usr The user address.
     */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external auth {
        require(block.timestamp > periodFinish, "Farm/period-no-finished");
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    function setRewardsDistribution(address _rewardsDistribution) external auth {
        rewardsDistribution = _rewardsDistribution;
    }

    /**
     * @notice Change the paused state of the contract
     * @dev Only the contract owner may call this.
     */
    function setPaused(bool _paused) external auth {
        // Ensure we're actually changing the state before we do anything
        if (_paused == paused) {
            return;
        }

        // Set our paused state.
        paused = _paused;

        // If applicable, set the last pause time.
        if (paused) {
            lastPauseTime = block.timestamp;
        }

        // Let everyone know that our pause state has changed.
        emit PauseChanged(paused);
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable().sub(lastUpdateTime).mul(rewardRate).mul(1e18).div(_totalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            _balances[account].mul(rewardPerToken().sub(userRewardPerTokenPaid[account])).div(1e18).add(
                rewards[account]
            );
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) external nonReentrant notPaused updateReward(msg.sender) {
        require(amount > 0, "Farm/invalid-amount");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        gem.transferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Farm/invalid-amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        gem.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardGem.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    function recoverERC20(address token, uint256 amt, address to) external auth {
        require(token != address(gem), "Farm/gem-not-allowed");
        GemAbstract(token).transfer(to, amt);
        emit Recovered(token, amt, to);
    }

    function notifyRewardAmount(uint256 reward) external onlyRewardsDistribution updateReward(address(0)) {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardGem.balanceOf(address(this));
        require(rewardRate <= balance.div(rewardsDuration), "Farm/invalid-reward");

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }
}
