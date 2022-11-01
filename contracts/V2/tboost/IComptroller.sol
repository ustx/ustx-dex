// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

interface IComptroller {
    //enable jToken as collateral
    function enterMarket(address jTokenAddress) external returns(uint256);

    //disable jToken as collateral
    function exitMarket(address jTokenAddress) external returns(uint256);

    //get account liquidity (error, liquidity margin, liquidity missing)
    function getAccountLiquidity(address account) external view returns(uint256, uint256, uint256);

    //preview account liquidity (error, liquidity margin, liquidity missing)
    function getHypotheticalAccountLiquidity(address account, address jTokenAddress, uint256 redeemTokens, uint256 borrowAmount) external view returns(uint256, uint256, uint256);

}
