// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.3.2 (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IStaking {

    /* ========== VIEWS ========== */

    function totalStaked() external view returns (uint256, uint256, uint256, uint256, uint256);
    function balanceOf(address account) external view returns (uint256, uint256, uint256,uint256, uint256);

	// Events
    event NewEpoch(uint256 epoch, uint256 reward, uint256 rateFree, uint256 rateL1, uint256 rateL2, uint256 rateL3, uint256 rateL4);
    event Staked(address indexed user, uint256 amount, uint256 stakeType);
    event Withdrawn(address indexed user, uint256 amount, uint256 stakeType);
    event RewardPaid(address indexed user, uint256 reward, uint256 stakeType);
    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);
}
