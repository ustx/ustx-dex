// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.3.2 (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IMerkleDistributor {
    function claim(uint256 merkleIndex, uint256 index, uint256 amount, bytes32[] calldata merkleProof) external;
}
