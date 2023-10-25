// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

/**
 * @dev Interface for Ergon events
 */
interface IEvents {
	// Events
    event NewJackpot(address indexed user, uint256 indexed jackpotType, uint256 amount);
    event Dispense(address indexed user, uint256 total, uint256 reward);
    event AdminAdded(address account);
    event AdminRemoved(address account);
}
