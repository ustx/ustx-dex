// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

interface IDex {
    //Buy USTX
    function buyTokenInput(uint256 stableSell, uint256 tIndex, uint256 minTokens) external returns (uint256);

    //Sell USTX
    function sellTokenInput(uint256 tokensSold, uint256 tIndex, uint256 minUsdts) external returns (uint256);

    //Buy preview
    function buyTokenInputPreview(uint256 usdtSold) view external returns (uint256);

    //Sell preview
    function sellTokenInputPreview(uint256 tokensSold) view external returns (uint256);

    //Get price
    function getPrice() external view returns (uint256);
}
