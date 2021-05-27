// UpStableToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;

import "./ERC20.sol";
import "./ERC20Detailed.sol";
import "./AdminRole.sol";
import "./Pausable.sol";


/// @title Up Stable Token eXperiment TRC20 token
/// @author USTX Team
/// @dev This contract implements the functionality of the USTX token.
contract UpStableToken is ERC20,ERC20Detailed,Pausable {
	//Variables
    uint256 private _basisPointsRate = 0;
    uint256 private constant MAX_SETTABLE_BASIS_POINTS = 100;
    address private _feeAddress;

	//Events
	event FeeChanged(uint256 feeBasisPoints);

	/**
	* @dev Constructor
	*
	*
	*/
	constructor()
	    ERC20Detailed("UpStableToken", "USTX", 6)
	    AdminRole(3)        //at least two administrators always in charge + the dex contract
	    public {
        	_feeAddress=_msgSender();
	    }

	/**
	* @dev Private function to calculate the fee (if applied)
	* @param value transaction value
	* @return fee amount
	*/
	function _calcFee(uint256 value) private view returns (uint256) {
		uint256 fee = (value.mul(_basisPointsRate)).div(10000);

		return fee;
	}

	/**
	* @dev Public function to transfer token (when not paused)
	* @param to destination address
	* @param value transaction value
	* @return true
	*/
	function transfer(address to, uint256 value) public whenNotPaused returns (bool) {
		uint256 fee = _calcFee(value);
		if (isAdmin(_msgSender())){   //no fees if sender is admin (DEX included)
			fee = 0;
		}
		uint256 sendAmount = value.sub(fee);

		if (fee > 0) {
			super.transfer(_feeAddress, fee);
		}
		super.transfer(to, sendAmount);

		return true;
	}

	/**
	* @dev Public function to transfer token from a third party (when not paused)
	* @param from source address
	* @param to destination address
	* @param value transaction value
	* @return true
	*/
	function transferFrom(address from, address to, uint256 value) public whenNotPaused returns (bool) {
		uint256 fee = _calcFee(value);
		if (isAdmin(_msgSender())){   //no fees if sender is admin (DEX included)
			fee = 0;
		}
		uint256 sendAmount = value.sub(fee);

		if (fee > 0 ) {
			super.transferFrom(from, _feeAddress, fee);
		}
		super.transferFrom(from, to, sendAmount);

		return true;
	}

	/**
	* @dev Public function to set fee percentage (only admin)
	* @param newBasisPoints fee percentage in basis points
	*
	*/
    function setFee(uint256 newBasisPoints) public onlyAdmin {
        // Ensure transparency by hardcoding limit beyond which fees can never be added
        require(newBasisPoints <= MAX_SETTABLE_BASIS_POINTS,"Fee cannot be set higher than MAX_SETTABLE_BASIS_POINTS");

        _basisPointsRate = newBasisPoints;

        emit FeeChanged(_basisPointsRate);
    }

	/**
	* @dev Public function to get current fee level
	* @return fee in basis points
	*
	*/
    function getFee() public view returns (uint256){
        // Ensure transparency by hardcoding limit beyond which fees can never be added
        return _basisPointsRate;
    }

	/**
	* @dev Public function to set fee destination address (only admin)
	* @param feeAddr fee destination account address
	*
	*/
	function setFeeAddress(address feeAddr) public onlyAdmin {
		require(feeAddr != address(0) && feeAddr != address(this));
		_feeAddress = feeAddr;
	}

	/**
	* @dev Public function to mint new tokens (only admin)
	* @param account destination account address
	* @param amount new tokens to mint
	* @return true
	*/
    function mint(address account, uint256 amount) public onlyAdmin returns (bool) {
        _mint(account, amount);
        return true;
    }

	/**
	* @dev Public function to burn tokens (from caller's account)
	* @param amount number of tokens to burn
	*
	*/
    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

	/**
	* @dev Public function to burn tokens (from third party's account with approval)
	* @param account target account
	* @param amount number of tokens to burn
	*/
    function burnFrom(address account, uint256 amount) public {
        _burnFrom(account, amount);
    }

	/**
	* @dev Public function to approve spending (when not paused)
	* @param spender authorized spender account
	* @param value permitted allowance
	*/
    function approve(address spender, uint256 value) public whenNotPaused returns (bool) {
        return super.approve(spender, value);
    }

	/**
	* @dev Public function to increase spending allowance (when not paused)
	* @param spender authorized spender account
	* @param addedValue allowance increase
	*/
    function increaseAllowance(address spender, uint256 addedValue) public whenNotPaused returns (bool) {
        return super.increaseAllowance(spender, addedValue);
    }

	/**
	* @dev Public function to reduce spending allowance (when not paused)
	* @param spender authorized spender account
	* @param subtractedValue allowance reduction
	*/
    function decreaseAllowance(address spender, uint256 subtractedValue) public whenNotPaused returns (bool) {
        return super.decreaseAllowance(spender, subtractedValue);
    }
}
