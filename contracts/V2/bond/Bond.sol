// Staking.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Roles.sol";
import "./Initializable.sol";


/// @title Up Stable Token eXperiment Bond contract
/// @author USTX Team
/// @dev This contract implements the bonds capability for USTX project

contract Bond is Initializable{
	using Roles for Roles.Role;

	/***********************************|
	|        Variables && Events        |
	|__________________________________*/


	//Variables
	bool private _notEntered;			//reentrancyguard state
	Roles.Role private _administrators;
	uint256 private _numAdmins;
	uint256 private _minAdmins;

    IERC20 public ustxToken;
    IERC20 public usdtToken;

    uint256 public activeBond;
    uint256 public redeemPrice;

    uint256 private _totalEmissions;
    uint256 private _totalRedeemed;

    uint256 private _taxRate;
    address private _taxWallet;

    uint256 private _bondEnable;

    address[] private _users;

    mapping(address => uint256) private _userIndex;         //user index in the users array
    mapping(address => uint256) private _userEmitted;        //total emitted amount in USTX
    mapping(address => uint256) private _userToBeRedeemed;      //amount of USTX still to be redeemed

    //Last V1 variable
    uint256 public version;

	// Events
    event NewEmission(address indexed user, uint256 indexed amount, uint256 indexed index);
    event Redeemed(address indexed user, uint256 indexed amount, uint256 indexed amountLeft);
    event Withdrawn(address indexed user, uint256 indexed amount);
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
		_taxWallet = msg.sender;
        _totalEmissions = 0;
        _totalRedeemed = 0;
        _taxRate = 50;            //Tax 5% when redeeming
        _bondEnable=1;
        _users.push(address(0));
        activeBond=1;           //incremental
        redeemPrice=10000;      //0.01 USDT, 6 decimals
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

    function getBalances() public view returns(uint256, uint256, uint256, uint256) {
        uint256 temp = _totalEmissions - _totalRedeemed;
        return (ustxToken.balanceOf(address(this)), _totalEmissions, _totalRedeemed, temp);
    }

    function balanceOf(address account) public view returns (uint256, uint256) {
        return (_userEmitted[account],_userToBeRedeemed[account]);
    }

    function getTax() public view returns (uint256) {
        return (_taxRate);
    }

    /* ========== BOND FUNCTIONS ========== */

    function newbond(uint256 amount) public nonReentrant {
        require(amount > 0, "Cannot emit 0");
        require(_bondEnable > 0, "Bond emission is not allowed");
        _totalEmissions += amount;

        if (_userToBeRedeemed[msg.sender]==0)
        {
            _users.push(msg.sender);
            _userIndex[msg.sender] = _users.length -1;
        }
        _userEmitted[msg.sender] += amount;
        ustxToken.transferFrom(msg.sender, address(this), amount);
        _userToBeRedeemed[msg.sender] += amount;

        emit NewEmission(msg.sender, amount, _userIndex[msg.sender]);
    }

    function _redeem(uint256 amount) internal returns(uint256) {
        address activeUser = _users[activeBond];
        uint256 available = _userToBeRedeemed[activeUser];
        uint256 tax;

        if (amount >= available) {
            amount = available;
            _userToBeRedeemed[activeUser] = 0;
            activeBond++;
        } else {
            _userToBeRedeemed[activeUser] -= amount;
        }

        require(amount > 0, "Nothing to redeem");

        tax = amount * redeemPrice * _taxRate / 1000 / 1000000;
        usdtToken.transferFrom(msg.sender, activeUser, amount * redeemPrice / 1000000 - tax);
        usdtToken.transferFrom(msg.sender, _taxWallet, tax);
        _totalRedeemed += amount;

        emit Redeemed(msg.sender, amount, _userToBeRedeemed[activeUser]);

        return amount;
    }

    function redeem(uint256 amount) public nonReentrant {
        uint256 realAmount = _redeem(amount);
        ustxToken.transfer(msg.sender, realAmount);         //send USTX to user
    }

    function redeemAndBurn(uint256 amount) public nonReentrant {
        uint256 realAmount = _redeem(amount);
        ustxToken.burn(realAmount);         //burn USTX
    }

    function withdraw() public nonReentrant {
        require(_userToBeRedeemed[msg.sender]>0, "Nothing to withdraw");

        uint256 amount = _userToBeRedeemed[msg.sender];

        _totalEmissions -= amount;
        _userToBeRedeemed[msg.sender] = 0;
        _userEmitted[msg.sender] -= amount;
        ustxToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }


	/**
	* @dev Function to set Token address (only admin)
	* @param ustxAddress address of the traded token contract
	*/
	function setUstxAddr(address ustxAddress) public onlyAdmin {
	    require(ustxAddress != address(0), "INVALID_ADDRESS");
		ustxToken = IERC20(ustxAddress);
	}

	/**
	* @dev Function to set Token address (only admin)
	* @param usdtAddress address of the traded token contract
	*/
	function setUsdtAddr(address usdtAddress) public onlyAdmin {
	    require(usdtAddress != address(0), "INVALID_ADDRESS");
		usdtToken = IERC20(usdtAddress);
	}

	/**
	* @dev Function to set taxes (only admin)
	* @param tax taxation percentage
    *
	*/
	function setTaxes(uint256 tax) public onlyAdmin {
	    require(tax <= 100, "Taxation needs to be lower than 10%");
        _taxRate = tax;
	}

	function setTaxWallet(address wallet) public onlyAdmin {
	    require(wallet != address(0), "INVALID_ADDRESS");
        _taxWallet = wallet;
	}

	/**
	* @dev Function to enable/disable staking (only admin)
	* @param enable enable bond emission
	*/
	function setEnable(uint256 enable) public onlyAdmin {
        _bondEnable = enable;
	}

	function setRedeemPrice(uint256 price) public onlyAdmin {
        redeemPrice = price;
	}

    /**
	* @dev Function to withdraw lost tokens balance (only admin)
	* @param tokenAddr Token address
	*/
	function withdrawToken(address tokenAddr) public onlyAdmin returns(uint256) {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");
		require(tokenAddr != address(ustxToken), "Cannot withdraw staked tokens");

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

}
