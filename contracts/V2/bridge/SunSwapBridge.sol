// SunSwapBridge.sol
// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./Roles.sol";
import "./IJustswapExchange.sol";
import "./IUstxDEX.sol";


/// @title Up Stable Token eXperiment SunSwap bridge
/// @author USTX Team
/// @dev This contract implements the interswap (USTX DEX <-> SunSwap) functionality for the USTX token.
// solhint-disable-next-line
contract SunSwapBridge {
	using Roles for Roles.Role;

	/***********************************|
	|        Variables && Events        |
	|__________________________________*/


	//Variables
	uint256 private _decimals;			// 6
	IUstxDEX private _ustxDex;	//USTX DEX address
    IJustswapExchange[5] private _scTrxPool; //SunSwap pools

	bool private _notEntered;			//reentrancyguard state
	Roles.Role private _administrators;
	uint256 private _numAdmins;
	uint256 private _minAdmins;

    IERC20[5] private _rt;    //reserve token address (element 0 is USDT)
	uint256[5] private _rtShift;       //reserve token decimal shift

	IERC20 private _token;	// address of USTX token

	// Events
	event TokenBuy(address indexed buyer, uint256 indexed trxSold, uint256 indexed tokensBought, uint256 tIndex);
	event TokenSell(address indexed buyer, uint256 indexed tokensSold, uint256 indexed trxBought, uint256 tIndex);
	event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);

	/**
	* @dev costructor
	*
	*/
    constructor() {
        _decimals = 6;
        _notEntered = true;
        _numAdmins=0;
		_addAdmin(_msgSender());		//default admin
		_minAdmins = 2;					//at least 2 admins in charge
    }


	/***********************************|
	|        AdminRole                  |
	|__________________________________*/

	modifier onlyAdmin() {
        require(isAdmin(_msgSender()), "AdminRole: caller does not have the Admin role");
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
        _removeAdmin(_msgSender());
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

	/***********************************|
	|        Context                    |
	|__________________________________*/

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

	/***********************************|
	|        Exchange Functions         |
	|__________________________________*/

  /**
   * @notice Convert TRX to Tokens.
   * @dev User specifies exact input (msg.value).
   * @dev User cannot specify minimum output or deadline.
   */
  fallback () external payable {
    _trxToTokenTransferInput(msg.value, 0, 1, _msgSender());
  }

	/**
	* @dev Public function to buy tokens and transfer them to recipient
	* @param minTokens minimum amount of tokens to buy
	* @param tIndex index of the reserve token to swap
	* @param recipient recipient of the transaction
	* @return number of tokens bought
	*/
	function trxToTokenTransferInput(uint256 tIndex, uint256 minTokens, address recipient) public payable returns(uint256) {
		require(recipient != address(this) && recipient != address(0),"Recipient cannot be this or address 0");
		require(tIndex<5, "INVALID_INDEX");

		return _trxToTokenTransferInput(msg.value,tIndex,minTokens,recipient);


	}

	/**
	* @dev Public function to buy tokens with TRX
	* @param minTokens minimum amount of tokens to buy
	* @param tIndex index of the reserve token to swap
	* @return number of tokens bought
	*/
	function trxToTokenInput(uint256 tIndex, uint256 minTokens) public payable returns(uint256) {
		require(tIndex<5, "INVALID_INDEX");

		return _trxToTokenTransferInput(msg.value,tIndex,minTokens,_msgSender());
	}

	/**
	* @dev Private function to buy tokens and transfer them to recipient
	* @param trxSell amount of TRX to sell
	* @param minTokens minimum amount of tokens to buy
	* @param tIndex index of the reserve token to swap
	* @param recipient recipient of the transaction
	* @return number of tokens bought
	*/
	function _trxToTokenTransferInput(uint256 trxSell, uint256 tIndex, uint256 minTokens, address recipient) private nonReentrant returns(uint256) {
		uint256 sc;
		uint256 tokensBought;

		sc = _scTrxPool[tIndex].trxToTokenSwapInput{value: trxSell}(1, block.timestamp+10);

		sc = sc / (10**_rtShift[tIndex]);

		tokensBought = _ustxDex.buyTokenTransferInput(sc, tIndex, minTokens, recipient);

		emit TokenBuy(recipient, trxSell, tokensBought, tIndex);

		return tokensBought;
	}

	/**
	* @dev Public function to sell tokens and get TRX
	* @param minTrx minimum amount of TRX to get
	* @param tIndex index of the reserve token to swap
	* @return number of tokens bought
	*/
	function tokenToTrxInput(uint256 tokenSell, uint256 tIndex, uint256 minTrx) public returns(uint256) {
		require(tIndex<5, "INVALID_INDEX");

		return _tokenToTrxTransferInput(_msgSender(), tokenSell, tIndex, minTrx, _msgSender());
	}

	/**
	* @dev Public function to sell tokens and transfer TRX to recipient
	* @param minTrx minimum amount of TRX to get
	* @param tIndex index of the reserve token to swap
	* @param recipient recipient of the transaction
	* @return number of TRX bought
	*/
	function tokenToTrxTransferInput(uint256 tokenSell, uint256 tIndex, uint256 minTrx, address recipient) public returns(uint256) {
		require(recipient != address(this) && recipient != address(0),"Recipient cannot be this or address 0");
		require(tIndex<5, "INVALID_INDEX");

		return _tokenToTrxTransferInput(_msgSender(), tokenSell, tIndex, minTrx, recipient);
	}

	/**
	* @dev Private function to sell tokens and transfer TRX to recipient
	* @param buyer address of buyer
	* @param tokenSell amount of tokens to sell
	* @param minTrx minimum amount of TRX to buy
	* @param tIndex index of the reserve token to swap
	* @param recipient recipient of the transaction
	* @return number of TRX bought
	*/
	function _tokenToTrxTransferInput(address buyer, uint256 tokenSell, uint256 tIndex, uint256 minTrx, address recipient) private nonReentrant returns(uint256) {
		uint256 sc;
		uint256 trxBought;

		_token.transferFrom(buyer,address(this),tokenSell);

		sc = _ustxDex.sellTokenInput(tokenSell, tIndex, 1);

		sc = sc * (10**_rtShift[tIndex]);

		trxBought = _scTrxPool[tIndex].tokenToTrxTransferInput(sc,minTrx, block.timestamp+10, recipient);

		emit TokenSell(recipient, tokenSell, trxBought, tIndex);

		return trxBought;
	}

	/**
	* @dev Function to set reserve token address (only admin)
	* @param tokenAddr address of the reserve token contract
	* @param swapAddr address of the swap pool
	* @param index token index in array 0-4
	* @param decimals number of decimals
	*/
	function setScTokenAddr(uint256 index, address tokenAddr, uint256 decimals, address payable swapAddr) public onlyAdmin {
		require(tokenAddr != address(0), "INVALID_ADDRESS");
		require(swapAddr != address(0),"INVALID_ADDRESS");
		require(index<5, "INVALID_INDEX");
		require(decimals>=6, "INVALID_DECIMALS");
		_rt[index] = IERC20(tokenAddr);
		_rtShift[index] = decimals-_decimals;
		_scTrxPool[index] = IJustswapExchange(swapAddr);
	}

	/**
	* @dev Function to set Token address (only admin)
	* @param tokenAddress address of the traded token contract
	*/
	function setTokenAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		_token = IERC20(tokenAddress);
	}

	/**
	* @dev Function to set Token address (only admin)
	* @param dexAddress address of the USTX DEX contract
	*/
	function setTokenSwapAddr(address dexAddress) public onlyAdmin {
	    require(dexAddress != address(0), "INVALID_ADDRESS");
		_ustxDex = IUstxDEX(dexAddress);
	}

	/**
	* @dev Function to approve token spending (only admin)
	* @param tokenAddr token address
	* @param destAddr recipient approval address
	* @param amount with token decimals
	*/
	function setApproval(address tokenAddr, address destAddr, uint256 amount) public onlyAdmin {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");
		require(destAddr != address(0), "INVALID_ADDRESS");
		require(amount > 0, "AMOUNT MUST BE > 0");

		IERC20 token = IERC20(tokenAddr);

	    token.approve(destAddr, amount);
	}

	/**
	* @dev Function to check token allowance (only admin)
	* @param tokenAddr token address
	* @param destAddr recipient approval address
	*/
	function checkAllowance(address tokenAddr, address destAddr) public view returns(uint256){
	    require(tokenAddr != address(0), "INVALID_ADDRESS");
		require(destAddr != address(0), "INVALID_ADDRESS");

		IERC20 token = IERC20(tokenAddr);

	    return token.allowance(address(this),destAddr);
	}

	/**
	* @dev Function to withdraw token balance (only admin)
	* @param tokenAddr Token address
	*/
	function withdrawToken(address tokenAddr) public onlyAdmin returns(uint256) {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");

		IERC20 token = IERC20(tokenAddr);

		uint256 balance = token.balanceOf(address(this));

		token.transfer(_msgSender(),balance);

		return balance;
	}

	/**
	* @dev Function to withdraw TRX balance (only admin)
	*/
    function withdrawTrx() public onlyAdmin returns(uint256){
        uint256 balance = address(this).balance;
		address payable rec = payable(_msgSender());
		(bool sent, ) = rec.call{value: balance}("");
		require(sent, "Failed to send TRX");
		return balance;
     }
}
