pragma experimental ABIEncoderV2;
pragma solidity ^0.6.12;

import "forge-std/Test.sol";
import {DSToken} from "ds-token/token.sol";
import {Farm} from "./Farm.sol";

contract FarmTest is Test {
    uint256 internal constant WAD = 10 ** 18;

    TestToken internal rewardGem;
    TestToken internal gem;
    Farm internal farm;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event PauseChanged(bool isPaused);
    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Recovered(address token, uint256 amt, address to);
    event File(bytes32 indexed what, uint256 data);
    event File(bytes32 indexed what, address data);

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "ERR");
        return a / b;
    }

    function setupReward(uint256 amt) internal {
        rewardGem.mint(amt);
        rewardGem.transfer(address(farm), amt);
        farm.notifyRewardAmount(amt);
    }

    function setupStakingToken(uint256 amt) internal {
        gem.mint(amt);
        gem.approve(address(farm), amt);
    }

    function setUp() public {
        rewardGem = new TestToken("SubDaoT", 18);
        gem = new TestToken("MKR", 18);

        farm = new Farm(address(this), address(rewardGem), address(gem));
    }

    function testConstructor() public {
        vm.expectEmit(true, true, true, true);
        emit Rely(address(this));
        Farm f = new Farm(address(this), address(rewardGem), address(gem));

        assertEq(address(f.rewardGem()), address(rewardGem));
        assertEq(address(f.gem()), address(gem));
        assertEq(f.rewardsDistribution(), address(this));
        assertEq(f.wards(address(this)), 1);
    }

    function testRelyDeny() public {
        assertEq(farm.wards(address(0)), 0);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Rely(address(0));

        farm.rely(address(0));

        assertEq(farm.wards(address(0)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Deny(address(0));

        farm.deny(address(0));

        assertEq(farm.wards(address(0)), 0);
    }

    function testFileRewardDistribution() public {
        farm.file(bytes32("rewardDistribution"), address(0));
        assertEq(farm.rewardsDistribution(), address(0));
    }

    function testRevertOnUnauthorizedMethods() public {
        vm.startPrank(address(0));

        vm.expectRevert("Farm/not-authorized");
        farm.rely(address(0));

        vm.expectRevert("Farm/not-authorized");
        farm.deny(address(0));

        vm.expectRevert("Farm/not-authorized");
        farm.file(bytes32("rewardsDistribution"), address(0));

        vm.expectRevert("Farm/not-authorized");
        farm.file(bytes32("rewardsDuration"), 1 days);

        vm.expectRevert("Farm/not-authorized");
        farm.setPaused(true);

        vm.expectRevert("Farm/not-authorized");
        farm.recoverERC20(address(0), 1, address(0));
    }

    function testRevertWhenPausedMethods() public {
        farm.setPaused(true);

        vm.expectRevert("Farm/is-paused");
        farm.stake(1);
    }

    function testSetPause() public {
        vm.expectEmit(true, true, true, true);
        emit PauseChanged(true);

        farm.setPaused(true);
        assertEq(farm.lastPauseTime(), block.timestamp);
    }

    function testRevertOnRecoverStakingToken() public {
        vm.expectRevert("Farm/gem-not-allowed");
        farm.recoverERC20(address(gem), 1, address(this));
    }

    function testRecoverERC20() public {
        TestToken t = new TestToken("TT", 18);
        t.mint(10);
        t.transfer(address(farm), 10);

        assertEq(t.balanceOf(address(farm)), 10);

        vm.expectEmit(true, true, true, true);
        emit Recovered(address(t), 10, address(this));

        farm.recoverERC20(address(t), 10, address(this));

        assertEq(t.balanceOf(address(farm)), 0);
        assertEq(t.balanceOf(address(this)), 10);
    }

    function testLastTimeRewardApplicable() public {
        assertEq(farm.lastTimeRewardApplicable(), 0);

        setupReward(10 * WAD);

        assertEq(farm.lastTimeRewardApplicable(), block.timestamp);
    }

    function testRewardPerToken() public {
        assertEq(farm.rewardPerToken(), 0);

        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        assertEq(farm.totalSupply(), 100 * WAD);

        setupReward(5000 * WAD);

        skip(1 days);

        assert(farm.rewardPerToken() > 0);
    }

    function testStakeEmitEvent() public {
        setupStakingToken(100 * WAD);

        vm.expectEmit(true, true, true, true);
        emit Staked(address(this), 100 * WAD);
        farm.stake(100 * WAD);
    }

    function testStaking() public {
        setupStakingToken(100 * WAD);

        uint256 gemBalance = gem.balanceOf(address(this));

        farm.stake(100 * WAD);

        assertEq(farm.balanceOf(address(this)), 100 * WAD);
        assertEq(gem.balanceOf(address(this)), gemBalance - 100 * WAD);
        assertEq(gem.balanceOf(address(farm)), 100 * WAD);
    }

    function testRevertOnZeroStake() public {
        vm.expectRevert("Farm/invalid-amount");
        farm.stake(0);
    }

    function testEarned() public {
        assertEq(farm.earned(address(this)), 0);

        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        setupReward(5000 * WAD);

        skip(1 days);

        assert(farm.earned(address(this)) > 0);
    }

    function testRewardRateIncreaseOnNewRewardBeforeDurationEnd() public {
        setupReward(5000 * WAD);

        uint256 rewardRate = farm.rewardRate();

        setupReward(5000 * WAD);

        assert(rewardRate > 0);
        assert(farm.rewardRate() > rewardRate);
    }

    function earnedShouldIncreaseAfterDuration() public {
        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        setupStakingToken(5000 * WAD);

        skip(7 days);

        uint256 earned = farm.earned(address(this));

        setupStakingToken(5000 * WAD);

        skip(7 days);

        assertEq(farm.earned(address(this)), earned + earned);
    }

    function testGetRewardEvent() public {
        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        setupReward(5000 * WAD);

        skip(1 days);

        vm.expectEmit(true, true, true, true);
        emit RewardPaid(address(this), farm.rewardRate() * 1 days);
        farm.getReward();
    }

    function testGetReward() public {
        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        setupReward(5000 * WAD);

        skip(1 days);

        uint256 rewardBalance = rewardGem.balanceOf(address(this));
        uint256 earned = farm.earned(address(this));

        farm.getReward();

        assert(farm.earned(address(this)) < earned);
        assert(rewardGem.balanceOf(address(this)) > rewardBalance);
    }

    function testFileRewardDurationEvent() public {
        vm.expectEmit(true, true, true, true);
        emit File(bytes32("rewardDuration"), 70 days);
        farm.file(bytes32("rewardDuration"), 70 days);
    }

    function testFileRewardDurationBeforeDistribution() public {
        assertEq(farm.rewardsDuration(), 7 days);

        farm.file(bytes32("rewardDuration"), 70 days);

        assertEq(farm.rewardsDuration(), 70 days);
    }

    function testRevertFileRewardDurationOnActiveDistribution() public {
        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        setupReward(100 * WAD);

        skip(1 days);

        vm.expectRevert("Farm/period-no-finished");
        farm.file(bytes32("rewardDuration"), 70 days);
    }

    function testFileRewardDurationAfterDistributionPeriod() public {
        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        setupReward(100 * WAD);

        skip(8 days);

        farm.file(bytes32("rewardDuration"), 70 days);
        assertEq(farm.rewardsDuration(), 70 days);
    }

    function testGetRewardForDuration() public {
        setupReward(5000 * WAD);

        uint256 rewardForDuration = farm.getRewardForDuration();
        uint256 rewardDuration = farm.rewardsDuration();
        uint256 rewardRate = farm.rewardRate();

        assert(rewardForDuration > 0);
        assertEq(rewardForDuration, rewardRate * rewardDuration);
    }

    function testWithdrawalEvent() public {
        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        vm.expectEmit(true, true, true, true);
        emit Withdrawn(address(this), 1 * WAD);
        farm.withdraw(1 * WAD);
    }

    function testFailtIfNothingToWithdraw() public {
        farm.withdraw(1);
    }

    function testRevertOnZeroWithdraw() public {
        vm.expectRevert("Farm/invalid-amount");
        farm.withdraw(0);
    }

    function testWithdrwal() public {
        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        uint256 initialStakeBalance = farm.balanceOf(address(this));

        farm.withdraw(100 * WAD);

        assertEq(initialStakeBalance, farm.balanceOf(address(this)) + 100 * WAD);
        assertEq(gem.balanceOf(address(this)), 100 * WAD);
    }

    function testExit() public {
        setupStakingToken(100 * WAD);
        farm.stake(100 * WAD);

        setupReward(500 * WAD);

        skip(1 days);

        farm.exit();

        assertEq(farm.earned(address(this)), 0);
        assertEq(gem.balanceOf(address(this)), 100 * WAD);
        assertEq(rewardGem.balanceOf(address(this)), farm.rewardRate() * 1 days);
    }

    function testNotifyRewardEvent() public {
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(100 * WAD);

        setupReward(100 * WAD);
    }

    function testRevertOnNotBeingRewardDistributor() public {
        vm.prank(address(0));
        vm.expectRevert("Farm/not-authorized");
        farm.notifyRewardAmount(1);
    }

    function testRevertOnRewardGreaterThenBalance() public {
        rewardGem.mint(100 * WAD);
        rewardGem.transfer(address(farm), 100 * WAD);

        vm.expectRevert("Farm/invalid-reward");
        farm.notifyRewardAmount(101 * WAD);
    }

    function testRevertOnRewardGreaterThenBalancePlusRollOverBalance() public {
        setupReward(100 * WAD);

        rewardGem.mint(100 * WAD);
        rewardGem.transfer(address(farm), 100 * WAD);

        vm.expectRevert("Farm/invalid-reward");
        farm.notifyRewardAmount(101 * WAD);
    }

    function testFarm() public {
        uint256 staked = 100 * WAD;

        setupStakingToken(staked);
        farm.stake(staked);

        setupReward(5000 * WAD);

        // Period finish should be 7 days from now
        assertEq(farm.periodFinish(), block.timestamp + 7 days);

        // Reward duration is 7 days, so we'll
        // skip by 6 days to prevent expiration
        skip(6 days);

        // Make sure we earned in proportion to reward per token
        assertEq(farm.earned(address(this)), (farm.rewardPerToken() * staked) / WAD);

        // Make sure we get staking token after withdrawal and we still have the same amount earned
        farm.withdraw(20 * WAD);
        assertEq(gem.balanceOf(address(this)), 20 * WAD);
        assertEq(farm.earned(address(this)), (farm.rewardPerToken() * staked) / WAD);

        // Get rewards
        farm.getReward();
        assertEq(rewardGem.balanceOf(address(this)), (farm.rewardPerToken() * staked) / WAD);
        assertEq(farm.earned(address(this)), 0);

        // exit
        farm.exit();
        assertEq(gem.balanceOf(address(this)), staked);
    }
}

contract TestToken is DSToken {
    constructor(string memory symbol_, uint8 decimals_) public DSToken(symbol_) {
        decimals = decimals_;
    }
}
