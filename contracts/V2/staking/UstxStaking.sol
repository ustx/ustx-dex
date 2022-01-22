// Staking.sol
// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Roles.sol";


/// @title Up Stable Token eXperiment Staking contract
/// @author USTX Team
/// @dev This contract implements the interswap (USTX DEX <-> SunSwap) functionality for the USTX token.
// solhint-disable-next-line
contract UstxStaking {
	using Roles for Roles.Role;

	/***********************************|
	|        Variables && Events        |
	|__________________________________*/


	//Variables
	bool private _notEntered;			//reentrancyguard state
	Roles.Role private _administrators;
	uint256 private _numAdmins;
	uint256 private _minAdmins;

    IERC20 public stakingToken;

    uint256 public currentEpoch;

    uint256 private _totalStaked;
    uint256 private _totalRewards;
    uint256 private _paidRewards;
    uint256 private _maxIter;
    uint256 private _lockDuration;
    uint256 private _lostRewards;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _lastUpdate;
    mapping(address => uint256) private _rewards;
    mapping(address => uint256) private _lockedTill;

    mapping(uint256 => uint256) private _rewardRates;

	// Events
    event NewEpoch(uint256 epoch, uint256 reward, uint256 rate);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);

	/**
	* @dev costructor
	*
	*/
    constructor() {
        _notEntered = true;
        _numAdmins=0;
		_addAdmin(msg.sender);		//default admin
		_minAdmins = 2;					//at least 2 admins in charge
        currentEpoch = 0;
        _totalRewards = 0;
        _paidRewards = 0;
        _maxIter = 52;      //maximum loop depth for rewards calculation
        _lockDuration = 8;  //8 epochs lock
        _lostRewards = 0;
    }


	/***********************************|
	|        AdminRole                  |
	|__________________________________*/

	modifier onlyAdmin() {
        require(isAdmin(msg.sender), "AdminRole: caller does not have the Admin role");
        _;
    }

    function isAdmin(address account) public view returns (bool) {
        return _administrators.has(account);
    }

    function addAdmin(address account) public onlyAdmin {
        _addAdmin(account);
    }

    function renounceAdmin() public {
        require(_numAdmins>_minAdmins, "There must always be a minimum number of admins in charge");
        _removeAdmin(msg.sender);
    }

    function _addAdmin(address account) internal {
        _administrators.add(account);
        _numAdmins++;
        emit AdminAdded(account);
    }

    function _removeAdmin(address account) internal {
        _administrators.remove(account);
        _numAdmins--;
        emit AdminRemoved(account);
    }

	/***********************************|
	|        ReentrancyGuard            |
	|__________________________________*/

	/**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_notEntered, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _notEntered = false;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _notEntered = true;
    }

    /* ========== VIEWS ========== */

    function totalStaked() public view returns (uint256) {
        return _totalStaked;
    }

    function allRewards() public view returns (uint256,uint256,uint256,uint256) {
        return (_totalRewards, _paidRewards, _totalRewards-_paidRewards, _lostRewards);       //total, paid, pending, lost
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function lastUpdate(address account) public view returns (uint256) {
        return _lastUpdate[account];
    }

     function earned(address account) public view returns (uint256) {
        uint256 temp=0;
        for (uint i=_lastUpdate[account];i<currentEpoch;i++) {
            temp += _rewardRates[i];
        }
        return (_rewards[account] + temp*_balances[account]/1e18);
    }

    function getRate(uint256 epoch) public view returns (uint256) {
        return _rewardRates[epoch];
    }

    function getLock(address account) public view returns (uint256) {
        uint256 lock = 0;
        if (currentEpoch <= _lockedTill[account]) {
            lock = _lockedTill[account]-currentEpoch + 1;
        }
        return lock;
    }

    /* ========== STAKING FUNCTIONS ========== */

    function stake(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        _totalStaked = _totalStaked + amount;

        if (_balances[msg.sender] == 0) {
            _lockedTill[msg.sender] = currentEpoch + _lockDuration;
        }
        _balances[msg.sender] += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    function unstake(uint256 amount) public nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        if (currentEpoch <= _lockedTill[msg.sender]) {
            _lostRewards += _rewards[msg.sender];
            _rewards[msg.sender] = 0;
        }
        _totalStaked = _totalStaked - amount;
        _balances[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        require(currentEpoch > _lockedTill[msg.sender], "Rewards are locked");
        uint256 reward = _rewards[msg.sender];
        if (reward > 0) {
            _paidRewards += reward;
            _rewards[msg.sender] = 0;
            stakingToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function compound() public nonReentrant updateReward(msg.sender) {
        require(currentEpoch > _lockedTill[msg.sender], "Rewards are locked, compounding not allowed");
        uint256 reward = _rewards[msg.sender];
        if (reward > 0) {
            _paidRewards += reward;
            _rewards[msg.sender] = 0;
            emit RewardPaid(msg.sender, reward);
            _totalStaked = _totalStaked + reward;
            _balances[msg.sender] += reward;
            emit Staked(msg.sender, reward);
        }
    }

    function exit() public nonReentrant updateReward(msg.sender) {
        _totalStaked -= _balances[msg.sender];
        uint256 balance = _balances[msg.sender];
        _balances[msg.sender] = 0;

        if (currentEpoch <= _lockedTill[msg.sender]) {
            _lostRewards += _rewards[msg.sender];
            _rewards[msg.sender] = 0;
        }
        uint256 reward = _rewards[msg.sender];
        _rewards[msg.sender] = 0;
        _paidRewards += reward;
        require(reward+balance>0,"Nothing to withdraw");
        stakingToken.transfer(msg.sender, reward+balance);

        emit RewardPaid(msg.sender, reward);
        emit Withdrawn(msg.sender, balance);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function newEpoch(uint256 reward) public onlyAdmin {
        require(reward>0,"Reward must be > 0");
        _rewardRates[currentEpoch] = (reward + _lostRewards) * 1e18 / _totalStaked;   //current epoch APY
        _lostRewards = 0;
        _totalRewards += reward;

        stakingToken.transferFrom(msg.sender, address(this), reward);

        emit NewEpoch(currentEpoch, reward, _rewardRates[currentEpoch]);

        currentEpoch++;
    }

    function editRate(uint256 epoch, uint256 newRate) public onlyAdmin {
        _rewardRates[epoch] = newRate;
    }

    function setMaxIter(uint256 maxIter) public onlyAdmin {
        _maxIter = maxIter;
    }

    function setLockDuration(uint256 duration) public onlyAdmin {
        require(duration < 20, "Reduce duration");
        _lockDuration = duration;
    }

	/**
	* @dev Function to set Token address (only admin)
	* @param tokenAddress address of the traded token contract
	*/
	function setTokenAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		stakingToken = IERC20(tokenAddress);
	}

    /**
	* @dev Function to withdraw token balance (only admin)
	* @param tokenAddr Token address
	*/
	function withdrawToken(address tokenAddr) public onlyAdmin returns(uint256) {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");
		require(tokenAddr != address(stakingToken), "Cannot withdraw staked tokens");

		IERC20 token = IERC20(tokenAddr);

		uint256 balance = token.balanceOf(address(this));

		token.transfer(msg.sender,balance);

		return balance;
	}

	/**
	* @dev Function to withdraw TRX balance (only admin)
	*/
    function withdrawTrx() public onlyAdmin returns(uint256){
        uint256 balance = address(this).balance;
		address payable rec = payable(msg.sender);
		(bool sent, ) = rec.call{value: balance}("");
		require(sent, "Failed to send TRX");
		return balance;
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        uint256 temp=0;
        uint256 loopEnd = currentEpoch;
        if ((loopEnd-_lastUpdate[account]) > _maxIter) {
            loopEnd = _lastUpdate[account]+_maxIter;
        }
        for (uint i=_lastUpdate[account];i<loopEnd;i++) {
            temp += _rewardRates[i];
        }
        _rewards[account]+=temp*_balances[account]/1e18;
        _lastUpdate[account] = loopEnd;
        _;
    }

}
