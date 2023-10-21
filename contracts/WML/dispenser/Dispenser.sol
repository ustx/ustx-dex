// Dispenser.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./IUniswapV2Router02.sol";
import "./Roles.sol";
import "./Initializable.sol";
import "./IEvents.sol";
import "./IBand.sol";


/// @title WML Luck Dispenser contract V0.1
/// @author USTX Team
/// @dev This contract implements the WML Luck Dispenser

contract Ergon is Initializable, IERC20, IEvents{
	using Roles for Roles.Role;

	/***********************************|
	|        Variables && Events        |
	|__________________________________*/


	//Ergon Variables
    bool private _notEntered;			//reentrancyguard state
    Roles.Role private _administrators;
    uint256 private _numAdmins;

    IBand public bandRef;
    IUniswapV2Router02 public JMRouter;
    IERC20 public wbttToken;
    IERC20 public wmlToken;

    uint256 public currentEpoch;

    uint256 public jackpotB;        //bronze
    uint256 public jackpotS;        //siver
    uint256 public jackpotG;        //gold
    uint256 public lackpotI;        //instawin

    uint256 private _minBetB;                  //minimum bet
    uint256 private _minBetS;                  //minimum bet
    uint256 private _minBetG;                  //minimum bet
    uint256 private _maxBet;                    //max bet

    uint256 private _winProbB;                  //winning probability for Bronze
    uint256 private _winProbS;                  //winning probability for Silver
    uint256 private _winProbG;                  //winning probability for Gold
    uint256 private _winPercI;                  //winding percentage for instawin
    uint256 private _jackpotRate;    //% of jackpot to distribute to winners

    uint256 private _buybackPerc;               //% buyback

    uint256 public dispenseRate;            //rate of dispensing in MH
    uint256 public dispenseAccounts;        //no of accounts to dispense in a single shot
    uint256 public dispenseMaxAmount;       //max dispense amount per account
    uint256 public dispenseEnable;

    uint256 public _randomSeed;         //random seed from Oracle

    uint256 public buybackTotal;

    //Last V1 variable
    uint256 public version;




	/**
	* @dev initializer
	*
	*/
    function initialize() public initializer {
        version=1;
        _notEntered = true;
        _numAdmins = 0;
		_addAdmin(msg.sender);		//default admin

        currentEpoch = 0;
        wbttToken = IERC20(0x23181F21DEa5936e24163FFABa4Ea3B316B57f3C);             //main
        JMRouter = IUniswapV2Router02(0x0C759476B4E74614D30e1F667455A4e1f2Da8ACb);  //main

        bandRef = IBand(0x8c064bCf7C0DA3B3b090BAbFE8f3323534D84d68);        //testnet

        _minBetB = 100000 * 10**18;         //100k BTT -> 0.04$
        _minBetS = 1000000 * 10**18;        // 1M BTT -> 0.4$
        _minBetG = 5000000 * 10**18;        // 5M BTT -> 2$
        _maxBet = 25000000 * 10**18;        // 25M BTT -> 10$

        _winProbB = 10;                     //1 in 10 wins
        _winProbS = 100;                     //1 in 100 wins
        _winProbG = 1000;                     //1 in 1000 wins
        _winPercI = 100;                    //100% return rate on instawin
        _jackpotRate = 70;                  //30% of jackpot remains in the pot after a win

        _buybackPerc = 50;                      //50% of bets to buyback WML from DEX

        dispenseRate = 100;                  //0.0001 of tokens to be distributed every shot
        dispenseAccounts = 100;             //100 accounts every shot
        dispenseMaxAmount = 1000;           //max 1000 token per account
        dispenseEnable = 1;
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
        require(_numAdmins>0, "There must always be one admin in charge");
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
    function getLimits() public view returns (uint256, uint256, uint256, uint256) {
        return (_minBetB, _minBetS, _minBetG, _maxBet);
    }

    /* ========== DEPOSIT FUNCTIONS ========== */

    function depositTrx() public payable nonReentrant {
        require(msg.value > 0, "Cannot deposit 0");
        require(_depositEnable > 0, "Deposit non allowed");

        uint256 ergToMint = _trxToErg(msg.value);
        _mint(msg.sender, ergToMint);

        uint256 toFreeze = freezableTrx();
        freezebalancev2(toFreeze,1);

        emit Deposit(msg.sender, msg.value);
    }

    /* ========== HOUSEKEEPING FUNCTIONS ========== */

    /* ========== REWARDS FUNCTIONS ========== */
    function claimJackpotReward() public nonReentrant {
        require(_lenderLastJackpotEpoch[msg.sender] < currentEpoch, "Jackpot reward already claimed");
        uint256 boost = _userStake(msg.sender) * _jackpotBoostRatio / balanceOf(msg.sender);
        if (boost > 1000) {
            boost = 1000;
        }
        uint256 reward = balanceOf(msg.sender) * boost * _jackpotRemaining / (_totalSupply - _jackpotErgClaimed)/ 1000;
        if (reward > 0) {
            address payable rec = payable(msg.sender);
    		(bool sent, ) = rec.call{value: reward}("");
    		require(sent, "Failed to send TRX");
            _lenderLastJackpotEpoch[msg.sender]=currentEpoch;
            _jackpotRemaining -= reward;
            _jackpotErgClaimed += balanceOf(msg.sender);
        }
    }


    /* ========== RESTRICTED FUNCTIONS ========== */
    function jackpotSetup(uint256 percB, uint256 percS, uint256 percG) public payable onlyAdmin {
        jackpotB += msg.value * percB / 100;
        jackpotS += msg.value * percS / 100;
        jackpotG += msg.value * percG / 100;
    }

	function setJmRouterAddr(address routerAddress) public onlyAdmin {
	    require(routerAddress != address(0), "INVALID_ADDRESS");
		JMRouter = IUniswapV2Router02(routerAddress);
	}

	function setWmlAddr(address wmlAddress) public onlyAdmin {
	    require(wmlAddress != address(0), "INVALID_ADDRESS");
		wmlToken = IERC20(wmlAddress);
	}

	function setBetLimits(uint256 minB, uint256 minS, uint256 minG, uint256 max) public onlyAdmin {
	    require(max > minG && minG > minS && minS > minB, "Check values");

	    _minBetB = minB;
	    _minBetS = minS;
        _minBetG = minG;
        _maxBet = max;
	}

	function setDispenseEnable(uint256 enable) public onlyAdmin {
	    dispenseEnable = enable;
	}

    /**
	* @dev Function to withdraw lost tokens balance (only admin)
	* @param tokenAddr Token address
	*/
	function withdrawToken(address tokenAddr) public onlyAdmin returns(uint256) {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");

		IERC20 token = IERC20(tokenAddr);

		uint256 balance = token.balanceOf(address(this));

		token.transfer(msg.sender,balance);

		return balance;
	}

    function withdrawFees() public onlyAdmin returns(uint256 fees){
        fees = _feesAccumulating;
		address payable rec = payable(msg.sender);
		(bool sent, ) = rec.call{value: fees}("");
		require(sent, "Failed to send BTT");
		_feesAccumulating = 0;

		return(fees);
    }
}
