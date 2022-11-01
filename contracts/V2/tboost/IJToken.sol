// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

interface IJToken {
    //Supply to JL
    function mint(uint256 mintAmount) external returns(uint256);

    //Withdraw from JL
    function redeemUnderlying(uint256 redeemAmount) external returns(uint256);

    //Borrow from JL
    function borrow(uint256 borrowAmount) external returns(uint256);

    //Repay borrow on JL (pass 2**256 - 1 to repay all)
    function repayBorrow(uint256 amount) external returns(uint256);

    //Get account balance: error, supply balance, borrow balance, exchange rate
    function getAccountSnapshot(address account) external view returns(uint256, uint256, uint256, uint256);
}
