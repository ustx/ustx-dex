// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

interface IFarm {
    //withdraw
    function withdraw(uint256 value) external;

    //deposit
    function deposit(uint256 value) external;

    //claim rewards
    function claim_rewards() external;

    //get deposited balance
    function balanceOf(address account) external view returns(uint256);

    //get claimable pending rewards
    function claimable_reward_for(address addr) external view returns(uint256);

}
