// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

/**
 * @dev Interface for WML events
 */
interface IEvents {
	// Events
    event AdminAdded(address account);
    event AdminRemoved(address account);
}
