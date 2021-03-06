# USTX contracts (V1)

* **AdminRole.sol**, based on OpenZeppelin v2.5.1
  * Modified to implement Admin role
* **Context.sol**, same as OpenZeppelin v2.5.1
* **ERC20.sol**, same as OpenZeppelin v2.5.1
* **ERC20Detailed.sol**, same as OpenZeppelin v2.5.1
* **IERC20.sol**, same as OpenZeppelin v2.5.1
* **Pausable.sol**, same as OpenZeppelin v2.5.1
* **ReentrancyGuard.sol**, same as OpenZeppelin v2.5.1
* **Roles.sol**, same as OpenZeppelin v2.5.1
* **SafeMath.sol**, same as OpenZeppelin v2.5.1
* **UpStableToken.sol**, based on OpenZeppelin v2.5.1
  * Deployed on Shasta testnet at address **TULFRD7gsdcjA4HAvT4FH4rgnfLi2To8iv**
  * Mintable
  * Burnable
  * Pausable
  * Some functions are restricted to Admin role
* **UstxDEX.sol**, implementation of the DEX functionality for the trade pair USTX/USDT
  * Deployed on Shasta testnet ad address **TSY5FUgRZz2wJQ7uAjWS3Ga5VqhPzXc4dg**
  * Pausable
  * Trade functions are reentrancy protected
  * USDT Liquidity is locked in. Owners cannot withdraw it
  * Flexible fee structure is provided, with separate buy and sell fees, hardcapped at 2%
  * Some functions are restricted to Admin role
  * Uses SafeMath
  * Implements launchpad functions, to sell a predetermined amount of tokens at a fixed price
  * Main trade functions are
    * buyTokenInput, to buy USTX tokens with an exact amount of USDT
    * buyTokenTransferInput, to buy USTX tokens with an exact amount of USDT and trasnfer them to a recipient
    * sellTokenInput, to sell an exact amount of USTX tokens and get USDT in exchange
    * sellTokenTransferInput, to sell an exact amount of USTX tokens and transfer the exchanged USDT to a recipient
    * buyTokenLaunchInput, to buy USTX tokens during launchpad
    * buyTokenLaunchTransferInput, to buy USTX during launchpad and transfer them to a recipient
    * buyTokenInputPreview, to preview amount of USTX in exchange for an exact amount of USDT
    * sellTokenInputPreview, to preview amount of USDT in exchange for an exact amount of USTX
