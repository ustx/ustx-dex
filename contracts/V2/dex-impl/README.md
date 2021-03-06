# USTX DEX Implementation contracts (V2)

* **UstxDEX.sol**, implementation of the DEX functionality with multiasset reserve
  * Deployed on mainnet at address **TT7EHYyThW1G1WBndya7RQpNSXFHyzeHfx**
  * Updated to support Solidity v0.8.0
  * Pausable
  * Trade functions are reentrancy protected
  * Reserve Liquidity is locked in. Owners cannot withdraw it
  * Flexible fee structure is provided, with separate buy and sell fees, hardcapped at 2%
  * Some functions are restricted to Admin role
  * Implements launchpad functions, to sell a predetermined amount of tokens at a fixed price
  * Main trade functions are
    * buyTokenInput, to buy USTX tokens with an exact amount of USDT (or USDC, USDJ, TUSD)
    * buyTokenTransferInput, to buy USTX tokens with an exact amount of USDT (or USDC, USDJ, TUSD) and transfer them to a recipient
    * sellTokenInput, to sell an exact amount of USTX tokens and get USDT (or USDC, USDJ, TUSD) in exchange
    * sellTokenTransferInput, to sell an exact amount of USTX tokens and transfer the exchanged USDT (or USDC, USDJ, TUSD) to a recipient
    * buyTokenLaunchInput, to buy USTX tokens during launchpad
    * buyTokenLaunchTransferInput, to buy USTX during launchpad and transfer them to a recipient
    * buyTokenInputPreview, to preview amount of USTX in exchange for an exact amount of USDT (or USDC, USDJ, TUSD)
    * sellTokenInputPreview, to preview amount of USDT (or USDC, USDJ, TUSD) in exchange for an exact amount of USTX
	* swapReserveTokens, to swap one reserve token for another 1:1 (onlyAdmin)
