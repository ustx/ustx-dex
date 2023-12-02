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

contract Dispense is Initializable, IEvents{
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
    address public JMWmlBttAddr;

    uint256 public jackpotB;        //bronze
    uint256 public jackpotS;        //siver
    uint256 public jackpotG;        //gold

    uint256 private _minBetB;                  //minimum bet
    uint256 private _minBetS;                  //minimum bet
    uint256 private _minBetG;                  //minimum bet
    uint256 private _maxBet;                    //max bet

    uint256 private _winProbB;                  //winning probability for Bronze
    uint256 private _winProbS;                  //winning probability for Silver
    uint256 private _winProbG;                  //winning probability for Gold
    uint256 private _rewardProb;                //reward probability for instawin
    uint256 private _rewardGain;
    uint256 private _rewardKnee;
    uint256 private _jackpotRate;    //% of jackpot to distribute to winners

    uint256 private _buybackPerc;               //% buyback
    address public feeAddr;                     //fee address
    uint256 private _feeRate;                   //% of fee on jackpot wins

    uint256 public dispenseRate;            //rate of dispensing in MH
    uint256 public dispenseAccounts;        //no of accounts to dispense in a single shot
    uint256 public dispenseMaxAmount;       //max dispense amount per account
    uint256 public dispenseEnable;

    uint256 public buybackTotal;
    uint256 public jackpotWonTotal;

    mapping(address => uint256) private _prevSeed;          //previous seed factor

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
        feeAddr = msg.sender;

        wbttToken = IERC20(0x23181F21DEa5936e24163FFABa4Ea3B316B57f3C);             //main
        JMRouter = IUniswapV2Router02(0x0C759476B4E74614D30e1F667455A4e1f2Da8ACb);  //main
        wmlToken = IERC20(0xB134503c1047d1F2c3Cb494991d79132980417d6);      //main

        bandRef = IBand(0xDA7a001b254CD22e46d3eAB04d937489c93174C3);        //main

        _minBetB = 100000 * 10**18;         //100k BTT -> 0.04$
        _minBetS = 1000000 * 10**18;        // 1M BTT -> 0.4$
        _minBetG = 5000000 * 10**18;        // 5M BTT -> 2$
        _maxBet = 25000000 * 10**18;        // 25M BTT -> 10$

        _winProbB = 7;                     //1 in 7 wins
        _winProbS = 23;                     //1 in 23 wins
        _winProbG = 97;                     //1 in 97 wins
        _rewardProb = 200;                    //200% probability range
        _rewardGain = 100;                       //unity gain
        _rewardKnee = 100;                       //50% knee point

        _jackpotRate = 70;                  //70% of jackpot is paid
        _feeRate = 10;                      //10% fee, 20% remains for next winner

        _buybackPerc = 50;                      //50% of bets to buyback WML from DEX

        dispenseRate = 100;                  //0.0001 of tokens to be distributed every shot
        dispenseAccounts = 100;             //100 accounts every shot
        dispenseMaxAmount = 1000 * 10**18;           //max 1000 token per account
        dispenseEnable = 0;
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

    function getJackpots() public view returns (uint256, uint256, uint256) {
        return (jackpotB, jackpotS, jackpotG);
    }

    function getWinProb() public view returns (uint256, uint256, uint256) {
        return (_winProbB, _winProbS, _winProbG);
    }

    function getPriceMcap() public view returns (uint256 price, uint256 mcap) {
        uint256 circulating = wmlToken.totalSupply() - wmlToken.balanceOf(address(this));

        IBand.ReferenceData memory data;
        data = bandRef.getReferenceData("BTT", "USD");

        price =  getWmlPrice() * data.rate / 10**18;

        mcap = circulating * price / 10**18;
    }

    function getWmlPrice() public view returns (uint256 price) {
        uint256 balWml = wmlToken.balanceOf(JMWmlBttAddr);
        uint256 balBtt = wbttToken.balanceOf(JMWmlBttAddr);
        price = balBtt * 10**18 / balWml;
    }

    /* ========== DISPENSE FUNCTIONS ========== */

    function getSeed(address user) public view returns(uint256 seed){
        IBand.ReferenceData memory data;
        data = bandRef.getReferenceData("BTC", "USD");

        seed = (uint256)(keccak256(abi.encodePacked(data.rate, user, block.timestamp)));
        if (seed == _prevSeed[user]){
            data = bandRef.getReferenceData("ETH", "USD");
            seed = (uint256)(keccak256(abi.encodePacked(data.rate, user, block.timestamp)));
        }
        require(seed != _prevSeed[user],"randomness too low");
        return seed;
    }

    function _buybackWml(uint256 bttAmount) internal returns(uint256 wmlAmount){
        address[] memory path = new address[](2);
        uint256[] memory amounts;

        path[0] = address(wbttToken);
        path[1] = address(wmlToken);
        amounts = JMRouter.swapExactETHForTokens{value:bttAmount}(1,path,address(this),block.timestamp+10);
        wmlAmount = amounts[1];
        return(wmlAmount);
    }

    function dispense() public payable nonReentrant returns(uint256 amount, uint256 reward, uint256 jackpot){
        require(msg.value >= _minBetB, "Buyback too low");
        require(msg.value <= _maxBet, "Buyback too big");

        uint256 seed = getSeed(msg.sender);
        _prevSeed[msg.sender] = seed;

        uint256 wmlBought = _incrementJackpot(msg.value);
        uint256 wmlEq = wmlBought * 100 / _buybackPerc;

        reward = (seed % _rewardProb) * wmlEq / 100;
        if (reward > wmlEq * _rewardKnee / 100){
            reward = wmlEq * _rewardKnee / 100 + (reward - wmlEq * _rewardKnee / 100) * _rewardGain / 100;
        }
        wmlToken.transfer(msg.sender, reward);

        amount = _distribute(seed);

        jackpot = _checkJackpot(seed, msg.value);
        jackpotWonTotal += jackpot;

        emit Dispense(msg.sender, amount, reward);
    }

    function _incrementJackpot(uint256 betAmount) internal returns(uint256 wmlBought){
        uint256 buybackBtt = betAmount * _buybackPerc / 100;
        buybackTotal += buybackBtt;
        wmlBought = _buybackWml(buybackBtt);
        uint256 bet = betAmount - buybackBtt;
        uint256 temp;

        if (betAmount<_minBetS) {           //bronze bet
            temp = bet / 2;              //50% to bronze
            jackpotB += temp;
            bet -= temp;
            temp = bet / 2;             //25% to silver
            jackpotS += temp;
            bet -= temp;
        } else if ( betAmount >= _minBetG) {        //gold bet
            temp = bet * 10 / 100;              //10% to bronze
            jackpotB += temp;
            bet -= temp;
            temp = bet * 30 / 90;             //30% to silver
            jackpotS += temp;
            bet -= temp;
        } else {                            //silver bet
            temp = bet * 20 / 100;              //20% to bronze
            jackpotB += temp;
            bet -= temp;
            temp = bet / 2;             //40% to silver
            jackpotS += temp;
            bet -= temp;
        }

        jackpotG += bet;           //rest to gold

        return(wmlBought);
    }

    function _distribute(uint256 seed) internal returns(uint256 amount){
        require(dispenseEnable > 0, "Dispense non allowed");
        amount = wmlToken.balanceOf(address(this)) * dispenseRate / 1000000;
        uint256 cap = dispenseAccounts * dispenseMaxAmount;
        if (amount > cap) {
            amount = cap;
        }

        uint256 perAccount = amount / dispenseAccounts;
        amount = 0;
        address dest;
        uint256 value;
        for (uint256 i; i < dispenseAccounts; i++) {
            dest = address(uint160(uint256(keccak256(abi.encodePacked(seed,i)))));
            value = uint256(keccak256(abi.encodePacked(seed,i))) % perAccount;
            wmlToken.transfer(dest, value);
            amount += value;
        }

        return(amount);
    }

    function _checkJackpot(uint256 seed, uint256 value) internal returns(uint256 win){
        if (value >= _minBetG) {
            win = _checkGold(seed);
        }
        if (value >= _minBetS) {
            win = _checkSilver(seed);
        }
        win = _checkBronze(seed);
        return(win);
    }

    function _checkBronze(uint256 seed) internal returns(uint256 win){
        if ((seed % _winProbB) == 0) {
            win = jackpotB * _jackpotRate / 100;
            jackpotB -= win;
            _sendBtt(win, msg.sender);
            emit NewJackpot(msg.sender,0,win);
            uint256 fee = jackpotB * _feeRate / 100;
            jackpotB -= fee;
            _sendBtt(fee, feeAddr);
        }
        return(win);
    }

    function _checkSilver(uint256 seed) internal returns(uint256 win){
        if ((seed % _winProbS) == 0) {
            win = jackpotS * _jackpotRate / 100;
            jackpotS -= win;
            _sendBtt(win, msg.sender);
            emit NewJackpot(msg.sender,1,win);
            uint256 fee = jackpotS * _feeRate / 100;
            jackpotS -= fee;
            _sendBtt(fee, feeAddr);
        }
        return(win);
    }

    function _checkGold(uint256 seed) internal returns(uint256 win){
        if ((seed % _winProbG) == 0) {
            win = jackpotG * _jackpotRate / 100;
            jackpotG -= win;
            _sendBtt(win, msg.sender);
            emit NewJackpot(msg.sender,2,win);
            uint256 fee = jackpotG * _feeRate / 100;
            jackpotG -= fee;
            _sendBtt(fee, feeAddr);
        }
        return(win);
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

	function setWmlPoolAddr(address wmlPoolAddress) public onlyAdmin {
	    require(wmlPoolAddress != address(0), "INVALID_ADDRESS");
		JMWmlBttAddr = wmlPoolAddress;
	}

	function setBandAddr(address bandAddress) public onlyAdmin {
	    require(bandAddress != address(0), "INVALID_ADDRESS");
		bandRef = IBand(bandAddress);
	}

	function setFeeAddr(address feeAddress) public onlyAdmin {
	    require(feeAddress != address(0), "INVALID_ADDRESS");
		feeAddr = feeAddress;
	}

	function setBetLimits(uint256 minB, uint256 minS, uint256 minG, uint256 max) public onlyAdmin {
	    require(max > minG && minG > minS && minS > minB, "Check values");

	    _minBetB = minB;
	    _minBetS = minS;
        _minBetG = minG;
        _maxBet = max;
	}

	function setProb(uint256 probB, uint256 probS, uint256 probG, uint256 rewardProb, uint256 rewardGain, uint256 rewardKnee) public onlyAdmin {
	    require(probG > probS && probS > probB && rewardProb >= 100 && rewardGain >= 100, "Check values");

	    _winProbB = probB;
	    _winProbS = probS;
        _winProbG = probG;
        _rewardProb = rewardProb;
        _rewardGain = rewardGain;
        _rewardKnee = rewardKnee;
	}

    function setPerc(uint256 jackpotRate, uint256 buybackPerc, uint256 feeRate) public onlyAdmin {
        require(jackpotRate > 50 && buybackPerc >10 && feeRate < 20, "Check values");

	    _jackpotRate = jackpotRate;
        _buybackPerc = buybackPerc;
        _feeRate = feeRate;
	}

	function setDispenseEnable(uint256 enable) public onlyAdmin {
	    dispenseEnable = enable;
	}

    function setDispensePar(uint256 rate, uint256 accounts, uint256 maxAmount) public onlyAdmin {
        require(rate < 1000 && accounts < 1000 && maxAmount < 10000 * 10**18, "Check values");

	    dispenseRate = rate;
        dispenseAccounts = accounts;
        dispenseMaxAmount = maxAmount;
	}

	function withdrawToken(address tokenAddr) public onlyAdmin returns(uint256) {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");

		IERC20 token = IERC20(tokenAddr);

		uint256 balance = token.balanceOf(address(this));

		token.transfer(msg.sender,balance);

		return balance;
	}

    function withdraw(uint256 amount) public onlyAdmin {
        if (amount == 0) {
            amount = address(this).balance;
        }
		_sendBtt(amount, msg.sender);
    }

    function _sendBtt(uint256 amount, address dest) internal {
        address payable rec = payable(dest);

		(bool sent, ) = rec.call{value: amount}("");
		require(sent, "Failed to send BTT");
    }
}
