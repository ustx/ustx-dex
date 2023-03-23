// UpStableToken.sol
// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.5.0;

import "./ERC20.sol";
import "./ERC20Detailed.sol";
import "./AdminRole.sol";
import "./Pausable.sol";


/// @title xSTC TRC20 token
/// @author USTX Team
///
contract ERG is ERC20,ERC20Detailed,Pausable {
	/**
	* @dev Constructor for xSTC, 6 decimals, 2 administrators
	*
	*
	*/
	constructor()
		public
	    ERC20Detailed("ERG", "ERG", 6)
	    AdminRole(2)        //at least two administrators always in charge
		{ }

	/**
	* @dev Public function to transfer token (when not paused)
	* @param to destination address
	* @param value transaction value
	* @return boolean
	*/
	function transfer(address to, uint256 value) public whenNotPaused returns (bool) {
		return super.transfer(to, value);
	}

	/**
	* @dev Public function to transfer token from a third party (when not paused)
	* @param from source address
	* @param to destination address
	* @param value transaction value
	* @return boolean
	*/
	function transferFrom(address from, address to, uint256 value) public whenNotPaused returns (bool) {
		return super.transferFrom(from, to, value);
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
