// Staking.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Roles.sol";
import "./Initializable.sol";


/// @title Up Stable Token eXperiment Staking contract V2
/// @author USTX Team
/// @dev This contract implements the second version of the staking feature for USTX holders

contract UstxStakingV2 is Initializable{
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

    uint256 private _totalStakedFree;
    uint256 private _totalStakedL;

    uint256 private _totalRewards;
    uint256 private _paidRewards;
    uint256 private _taxes;
    uint256 private _tax;               //% per epoch

    uint256 private _lockDuration;
    uint256 private _extDuration;


    uint256 private _stakeFreeEnable;
    uint256 private _stakeLEnable;

    mapping(address => uint256) private _balancesFree;
    mapping(address => uint256) private _lastUpdateFree;
    mapping(address => uint256) private _rewardsFree;

    mapping(address => uint256) private _balancesL;
    mapping(address => uint256) private _lastUpdateL;
    mapping(address => uint256) private _rewardsL;
    mapping(address => uint256) private _lockedTill;

    mapping(uint256 => uint256) private _rewardRatesFree;
    mapping(uint256 => uint256) private _rewardRatesL;

    //Last V1 variable
    uint256 public version;

	// Events
    event NewEpoch(uint256 epoch, uint256 reward, uint256 rateFree, uint256 rateL);
    event Staked(address indexed user, uint256 amount, uint256 stakeType);
    event Withdrawn(address indexed user, uint256 amount, uint256 stakeType);
    event RewardPaid(address indexed user, uint256 reward, uint256 stakeType);
    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);

	/**
	* @dev initializer
	*
	*/
    function initialize() public initializer {
        version=1;
        _notEntered = true;
        _numAdmins=0;
		_addAdmin(msg.sender);		//default admin
		_minAdmins = 2;					//at least 2 admins in charge
        currentEpoch = 0;
        _totalRewards = 0;
        _paidRewards = 0;
        _lockDuration = 26;  //6 months lock
        _extDuration = 13;  //3 months extension on new operations
        _tax = 10;            //Tax 1% per epoch remaining (in 1000s)
        _stakeFreeEnable=1;
        _stakeLEnable=1;
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

    function totalStaked() public view returns (uint256, uint256) {
        return (_totalStakedFree, _totalStakedL);
    }

    function getBalances() public view returns(uint256, uint256, uint256, uint256) {
        uint256 temp = _totalStakedFree + _totalStakedL;
        return (stakingToken.balanceOf(address(this)), temp, _taxes, _totalRewards-_paidRewards);
    }

    function allRewards() public view returns (uint256,uint256,uint256) {
        return (_totalRewards, _paidRewards, _totalRewards-_paidRewards);       //total, paid, pending
    }

    function balanceOf(address account) public view returns (uint256, uint256) {
        return (_balancesFree[account],_balancesL[account]);
    }

    function lastUpdate(address account) public view returns (uint256,uint256) {
        return (_lastUpdateFree[account],_lastUpdateL[account]);
    }

    function getStakeEnable() public view returns (uint256,uint256) {
        return (_stakeFreeEnable, _stakeLEnable);
    }

    function getTax() public view returns (uint256) {
        return (_tax);
    }

    function earned(address account) public view returns (uint256, uint256) {
        uint256 temp=0;
        uint256 rFree=0;
        uint256 rL=0;
        uint256 i;

        for (i=_lastUpdateFree[account];i<currentEpoch;i++) {
            temp += _rewardRatesFree[i];
        }
        rFree = _rewardsFree[account] + temp*_balancesFree[account]/1e18;

        temp = 0;
        for (i=_lastUpdateL[account];i<currentEpoch;i++) {
            temp += _rewardRatesL[i];
        }
        rL = _rewardsL[account] + temp*_balancesL[account]/1e18;

        return (rFree, rL);
    }

    function getRates(uint256 epoch) public view returns (uint256,uint256) {
        return (_rewardRatesFree[epoch], _rewardRatesL[epoch]);
    }

    function getLock(address account) public view returns (uint256, uint256) {
        uint256 lock = 0;

        if (currentEpoch <= _lockedTill[account]) {
            lock = _lockedTill[account]-currentEpoch + 1;
        }

        return (0,lock);
    }

    function calcRewardFromAPY(uint256 APYFree, uint256 APYL) public view returns (uint256, uint256) {
        uint256 rFree;
        uint256 rL;

        rFree = _calcRewardFree(APYFree);
        rL = _calcRewardL(APYL);

        return (rFree, rL);
    }

    function _calcRewardFree(uint256 APY) internal view returns (uint256) {
        uint256 temp;
        uint256 reward;

        temp = APY *1e15 / 52;      //normalized yield per epoch. APY in 1000s
        reward = temp * _totalStakedFree / 1e18;

        return (reward);
    }

    function _calcRewardL(uint256 APY) internal view returns (uint256) {
        uint256 temp;
        uint256 reward;

        temp = APY *1e15 / 52;      //normalized yield per epoch. APY in 1000s
        reward = temp * _totalStakedL    / 1e18;

        return (reward);
    }

    /* ========== STAKE FUNCTIONS ========== */

    function stakeFree(uint256 amount) public nonReentrant updateRewardFree(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        require(_stakeFreeEnable > 0, "Free staking is not open");
        _totalStakedFree += amount;

        _balancesFree[msg.sender] += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, 0);
    }

    function stakeLock(uint256 amount) public nonReentrant updateRewardL(msg.sender) {
        require(amount > 0, "Cannot stake 0");
        require(_stakeLEnable > 0, "Locked Staking is not open");
        _totalStakedL += amount;

        if (_balancesL[msg.sender] == 0) {
            _lockedTill[msg.sender] = currentEpoch + _lockDuration;     //set base lock
        }
        if (currentEpoch + _extDuration > _lockedTill[msg.sender]) {
            _lockedTill[msg.sender] = currentEpoch + _extDuration;      //extend lock
        }
        _balancesL[msg.sender] += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, 1);
    }


    /* ========== COMPOUND FUNCTION ========== */
    function compoundFree() public nonReentrant updateRewardFree(msg.sender) {
        uint256 reward = _rewardsFree[msg.sender];
        if (reward > 0) {
            _paidRewards += reward;
            _rewardsFree[msg.sender] = 0;
            emit RewardPaid(msg.sender, reward, 0);
            _totalStakedFree += reward;
            _balancesFree[msg.sender] += reward;
            emit Staked(msg.sender, reward, 0);
        }
    }

    function compoundL() public nonReentrant updateRewardL(msg.sender) {
        uint256 reward = _rewardsL[msg.sender];
        if (reward > 0) {
            _paidRewards += reward;
            _rewardsL[msg.sender] = 0;
            emit RewardPaid(msg.sender, reward, 1);
            _totalStakedL += reward;
            _balancesL[msg.sender] += reward;
            emit Staked(msg.sender, reward, 1);
            if (currentEpoch + _extDuration > _lockedTill[msg.sender]) {
                _lockedTill[msg.sender] = currentEpoch + _extDuration;      //extend lock
            }
        }
    }

    /* ========== UNSTAKE FUNCTIONS ========== */
    function unstakeFree(uint256 amount) public nonReentrant updateRewardFree(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(amount <= _balancesFree[msg.sender], "Amount exceeds balance");

        _totalStakedFree -= amount;
        _balancesFree[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, 0);
    }

    function unstakeL(uint256 amount) public nonReentrant updateRewardL(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        require(amount <= _balancesL[msg.sender], "Amount exceeds balance");
        uint256 part = 0;
        uint256 tax = 0;

        if (currentEpoch <= _lockedTill[msg.sender]) {
            part = amount * 1e6 / _balancesL[msg.sender];      //fraction of balance to unstake
            tax = _rewardsL[msg.sender]*part/1e6;             //rewards lost
            _taxes += tax;
            _totalRewards -= tax;
            _rewardsL[msg.sender] = _rewardsL[msg.sender]-tax;   //remaining rewards
            tax = (_lockedTill[msg.sender]-currentEpoch + 1)*_tax;   //in 1000s
            tax = tax * part * _balancesL[msg.sender] / 1e9;      //taxes
        }
        _totalStakedL -= amount;
        _balancesL[msg.sender] -= amount;

        _taxes += tax;
        stakingToken.transfer(msg.sender, amount-tax);

        emit Withdrawn(msg.sender, amount, 1);
    }

    /* ========== REWARDS FUNCTIONS ========== */
    function getRewardFree() public nonReentrant updateRewardFree(msg.sender) {
        uint256 reward = _rewardsFree[msg.sender];
        if (reward > 0) {
            _paidRewards += reward;
            _rewardsFree[msg.sender] = 0;
            stakingToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward, 0);
        }
    }

    function getRewardL() public nonReentrant updateRewardL(msg.sender) {
        require(currentEpoch > _lockedTill[msg.sender], "Rewards are locked");
        uint256 reward = _rewardsL[msg.sender];
        if (reward > 0) {
            _paidRewards += reward;
            _rewardsL[msg.sender] = 0;
            stakingToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward, 1);
        }
    }

    /* ========== EXIT FUNCTIONS ========== */
    function exitFree() public nonReentrant updateRewardFree(msg.sender) {
        _totalStakedFree -= _balancesFree[msg.sender];
        uint256 balance = _balancesFree[msg.sender];
        _balancesFree[msg.sender] = 0;

        uint256 reward = _rewardsFree[msg.sender];
        _rewardsFree[msg.sender] = 0;
        _paidRewards += reward;
        require(reward+balance>0,"Nothing to withdraw");
        stakingToken.transfer(msg.sender, reward+balance);

        emit RewardPaid(msg.sender, reward, 0);
        emit Withdrawn(msg.sender, balance, 0);
    }

    function exitL() public nonReentrant updateRewardL(msg.sender) {
        _totalStakedL -= _balancesL[msg.sender];
        uint256 balance = _balancesL[msg.sender];
        _balancesL[msg.sender] = 0;

        uint256 tax = 0;
        if (currentEpoch <= _lockedTill[msg.sender]) {
            _taxes += _rewardsL[msg.sender];
            _totalRewards -= _rewardsL[msg.sender];
            _rewardsL[msg.sender] = 0;
            tax = balance * _tax * (_lockedTill[msg.sender] - currentEpoch + 1) / 1e3;
            _taxes += tax;
        }
        uint256 reward = _rewardsL[msg.sender];
        _rewardsL[msg.sender] = 0;
        _paidRewards += reward;
        require(reward+balance-tax>0,"Nothing to withdraw");
        stakingToken.transfer(msg.sender, reward+balance-tax);

        emit RewardPaid(msg.sender, reward, 1);
        emit Withdrawn(msg.sender, balance-tax, 1);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function newEpoch(uint256 rFree, uint256 rL) public onlyAdmin {
        require(rFree+rL > 0,"Reward must be > 0");

        _rewardRatesFree[currentEpoch] = rFree * 1e18 / _totalStakedFree;   //current epoch APY
        _totalRewards += rFree;

        _rewardRatesL[currentEpoch] = rL * 1e18 / _totalStakedL;   //current epoch APY
        _totalRewards += rL;

        stakingToken.transferFrom(msg.sender, address(this), rFree+rL);

        emit NewEpoch(currentEpoch, rFree+rL, _rewardRatesFree[currentEpoch], _rewardRatesL[currentEpoch]);

        currentEpoch++;
    }

    function setLockDuration(uint256 lockWeeks, uint256 extWeeks) public onlyAdmin {
        require(lockWeeks <= 52, "Reduce Lock duration");
        require(extWeeks <= 26, "Reduce Extend duration");

        _lockDuration = lockWeeks;
        _extDuration = extWeeks;

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
	* @dev Function to set taxes (only admin)
	* @param tax taxation percentage for lock1
    *
	*/
	function setTaxes(uint256 tax) public onlyAdmin {
	    require(tax <= 10, "Taxation needs to be lower than 1% per epoch");
        _tax = tax;
	}

	/**
	* @dev Function to enable/disable staking (only admin)
	* @param enableFree free staking enable
    * @param enableLocked locked staking enable
	*/
	function setStakeEnable(uint256 enableFree, uint256 enableLocked) public onlyAdmin {
        _stakeFreeEnable = enableFree;
        _stakeLEnable = enableLocked;
	}

    /**
	* @dev Function to withdraw lost tokens balance (only admin)
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
	* @dev Function to withdraw taxes (only admin)
	*
	*/
	function withdrawTaxes() public onlyAdmin returns(uint256) {
        uint256 temp;

        stakingToken.transfer(msg.sender,_taxes);
        temp = _taxes;
        _taxes = 0;

		return temp;
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

    modifier updateRewardFree(address account) {
        uint256 temp=0;

        for (uint i=_lastUpdateFree[account];i<currentEpoch;i++) {
            temp += _rewardRatesFree[i];
        }
        _rewardsFree[account]+=temp*_balancesFree[account]/1e18;
        _lastUpdateFree[account] = currentEpoch;
        _;
    }

    modifier updateRewardL(address account) {
        uint256 temp=0;

        for (uint i=_lastUpdateL[account];i<currentEpoch;i++) {
            temp += _rewardRatesL[i];
        }
        _rewardsL[account]+=temp*_balancesL[account]/1e18;
        _lastUpdateL[account] = currentEpoch;
        _;
    }

}
