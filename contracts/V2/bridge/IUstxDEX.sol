// SunSwapBridge.sol
// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;


/// @title Up Stable Token eXperiment SunSwap bridge
/// @author USTX Team
/// @dev This contract implements the DEX functionality for the USTX token (v2).
// solhint-disable-next-line
interface IUstxDEX {

	// Events
	event TokenBuy(address indexed buyer, uint256 indexed usdtSold, uint256 indexed tokensBought, uint256 price, uint256 tIndex);
	event TokenSell(address indexed buyer, uint256 indexed tokensSold, uint256 indexed usdtBought, uint256 price, uint256 tIndex);
	event Snapshot(address indexed operator, uint256 indexed reserveBalance, uint256 indexed tokenBalance);
	event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);


	/***********************************|
	|        Exchange Functions         |
	|__________________________________*/

	/**
	* @dev Public function to preview token purchase with exact input in USDT
	* @param usdtSold amount of USDT to sell
	* @return number of tokens that can be purchased with input usdtSold
	*/
	function buyTokenInputPreview(uint256 usdtSold) external view returns (uint256);

	/**
	* @dev Public function to preview token sale with exact input in tokens
	* @param tokensSold amount of token to sell
	* @return Amount of USDT that can be bought with input Tokens.
	*/
	function sellTokenInputPreview(uint256 tokensSold) external view returns (uint256);

	/**
	* @dev Public function to buy tokens during launchpad
	* @param rSell amount of UDST to sell
	* @param minTokens minimum amount of tokens to buy
	* @return number of tokens bought
	*/
	function  buyTokenLaunchInput(uint256 rSell, uint256 tIndex, uint256 minTokens) external returns (uint256);

	/**
	* @dev Public function to buy tokens during launchpad and transfer them to recipient
	* @param rSell amount of UDST to sell
	* @param minTokens minimum amount of tokens to buy
	* @param recipient recipient of the transaction
	* @return number of tokens bought
	*/
	function buyTokenLaunchTransferInput(uint256 rSell, uint256 tIndex, uint256 minTokens, address recipient) external returns(uint256);

	/**
	* @dev Public function to buy tokens
	* @param rSell amount of UDST to sell
	* @param minTokens minimum amount of tokens to buy
	* @param tIndex index of the reserve token to swap
	* @return number of tokens bought
	*/
	function  buyTokenInput(uint256 rSell, uint256 tIndex, uint256 minTokens) external returns (uint256);

	/**
	* @dev Public function to buy tokens and transfer them to recipient
	* @param rSell amount of UDST to sell
	* @param minTokens minimum amount of tokens to buy
	* @param tIndex index of the reserve token to swap
	* @param recipient recipient of the transaction
	* @return number of tokens bought
	*/
	function buyTokenTransferInput(uint256 rSell, uint256 tIndex, uint256 minTokens, address recipient) external returns(uint256);

	/**
	* @dev Public function to sell tokens
	* @param tokensSold number of tokens to sell
	* @param minUsdts minimum number of UDST to buy
	* @return number of USDTs bought
	*/
	function sellTokenInput(uint256 tokensSold, uint256 tIndex, uint256 minUsdts) external returns (uint256);

	/**
	* @dev Public function to sell tokens and trasnfer USDT to recipient
	* @param tokensSold number of tokens to sell
	* @param minUsdts minimum number of UDST to buy
	* @param recipient recipient of the transaction
	* @return number of USDTs bought
	*/
	function sellTokenTransferInput(uint256 tokensSold, uint256 tIndex, uint256 minUsdts, address recipient) external returns (uint256);


	/**************************************|
	|     Getter and Setter Functions      |
	|_____________________________________*/

	/**
	* @dev Function to get current price
	* @return current price
	*
	*/
	function getPrice() external view returns (uint256);

}
