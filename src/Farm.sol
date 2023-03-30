pragma solidity ^0.8.14;

import {GemAbstract} from "dss-interfaces/ERC/GemAbstract.sol";

contract Farm {
    GemAbstract public immutable rewardGem;
    GemAbstract public immutable gem;

    // @notice Addresses with admin access on this contract. `wards[usr]`.
    mapping(address => uint256) public wards;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    uint256 public live;
    uint256 public periodFinish = 0;
    uint256 public rewardRate = 0;
    uint256 public rewardsDuration = 7 days;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    address public rewardsDistribution;

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

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
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. Currently the supported values are: "rewardDuration".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, uint256 data);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. Currently the supported values are: "rewardsDistribution".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice Recover ERC20 token `amt` to `usr`.
     * @param token The token address.
     * @param usr The destination address.
     * @param amt The amount of `token` flushed out.
     */
    event Yank(address indexed token, address indexed usr, uint256 amt);

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Recovered(address token, uint256 amt, address to);

    /**
     * @notice Only addresses with admin access can call methods with this modifier.
     */
    modifier auth() {
        require(wards[msg.sender] == 1, "Farm/not-authorized");
        _;
    }

    modifier isLive() {
        require(live == 1, "Farm/not-live");
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

    constructor(address _rewardsDistribution, address _rewardGem, address _gem) {
        rewardGem = GemAbstract(_rewardGem);
        gem = GemAbstract(_gem);
        rewardsDistribution = _rewardsDistribution;

        live = 1;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    /*//////////////////////////////////
               Authorization
    //////////////////////////////////*/

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

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    /**
     * @notice Updates a contract parameter.
     * @dev Reward duration can be updated only when previouse distribution is done
     * @param what The changed parameter name. `rewardDuration`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, uint256 data) external auth {
        if (what == "rewardDuration") {
            require(block.timestamp > periodFinish, "Farm/period-no-finished");
            rewardsDuration = data;
        } else {
            revert("Farm/unrecognised-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. `rewardDistribution`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external auth {
        if (what == "rewardDistribution") {
            rewardsDistribution = data;
        } else {
            revert("Farm/unrecognised-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Cage farm
     */
    function cage() external auth {
        live = 0;
    }

    /**
     * @notice Escape from cage
     */
    function escape() external auth {
        live = 1;
    }

    /*//////////////////////////////////
               View
    //////////////////////////////////*/

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
            _add(
                rewardPerTokenStored,
                _div(_mul(_sub(lastTimeRewardApplicable(), lastUpdateTime), rewardRate * 1e18), _totalSupply)
            );
    }

    function earned(address account) public view returns (uint256) {
        return
            _add(
                _div(_mul(_balances[account], _sub(rewardPerToken(), userRewardPerTokenPaid[account])), 1e18),
                rewards[account]
            );
    }

    function getRewardForDuration() external view returns (uint256) {
        return _mul(rewardRate, rewardsDuration);
    }

    /*//////////////////////////////////
               Operations
    //////////////////////////////////*/

    function stake(uint256 amount) external isLive updateReward(msg.sender) {
        require(amount > 0, "Farm/invalid-amount");

        _totalSupply = _add(_totalSupply, amount);
        _balances[msg.sender] = _add(_balances[msg.sender], amount);
        gem.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public updateReward(msg.sender) {
        require(amount > 0, "Farm/invalid-amount");

        _totalSupply = _sub(_totalSupply, amount);
        _balances[msg.sender] = _sub(_balances[msg.sender], amount);
        gem.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public updateReward(msg.sender) {
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

    /**
     * @notice Flushes out `amt` of `token` sitting in this contract to `usr` address.
     * @dev Can only be called by the admin.
     * @param token Token address.
     * @param amt Token amount.
     * @param usr Destination address.
     */
    function yank(address token, uint256 amt, address usr) external auth {
        require(token != address(gem), "Farm/gem-not-allowed");

        GemAbstract(token).transfer(usr, amt);

        emit Yank(token, usr, amt);
    }

    function notifyRewardAmount(uint256 reward) external updateReward(address(0)) {
        require(wards[msg.sender] == 1 || msg.sender == rewardsDistribution, "Farm/not-authorized");

        if (block.timestamp >= periodFinish) {
            rewardRate = _div(reward, rewardsDuration);
        } else {
            uint256 remaining = _sub(periodFinish, block.timestamp);
            uint256 leftover = _mul(remaining, rewardRate);
            rewardRate = _div(_add(reward, leftover), rewardsDuration);
        }

        // Ensure the provided reward amount is not more than the balance in the contract.
        // This keeps the reward rate in the right range, preventing overflows due to
        // very high values of rewardRate in the earned and rewardsPerToken functions;
        // Reward + leftover must be less than 2^256 / 10^18 to avoid overflow.
        uint balance = rewardGem.balanceOf(address(this));
        require(rewardRate <= _div(balance, rewardsDuration), "Farm/invalid-reward");

        lastUpdateTime = block.timestamp;
        periodFinish = _add(block.timestamp, rewardsDuration);

        emit RewardAdded(reward);
    }

    /*//////////////////////////////////
                    Math
    //////////////////////////////////*/

    function _add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require((z = x + y) >= x, "Math/add-overflow");
        }
    }

    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require((z = x - y) <= x, "Math/sub-overflow");
        }
    }

    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require(y == 0 || (z = x * y) / y == x, "Math/mul-overflow");
        }
    }

    function _div(uint x, uint y) internal pure returns (uint z) {
        unchecked {
            require(y > 0, "Math/divide-by-zero");
            return x / y;
        }
    }
}
