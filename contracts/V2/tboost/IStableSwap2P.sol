// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

interface IStableSwap2P {
    function exchange(uint128 i, uint128 j, uint256 dx, uint256 min_dy) external;

    function get_dy(uint128 i, uint128 j, uint256 dx) external view returns(uint256);
}
