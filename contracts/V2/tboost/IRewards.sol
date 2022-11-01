// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

interface IRewards {

    //claim rewards
    function claim(bytes32 gauge_addr) external;

}
