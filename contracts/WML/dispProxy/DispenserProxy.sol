pragma solidity ^0.8.0;
// solhint-disable-next-line
// SPDX-License-Identifier: MIT

import "./TransparentUpgradeableProxy.sol";

contract DispenserProxy is TransparentUpgradeableProxy {
    /**
     * Takes logic contract implementation address and admin address
     */
    constructor(address _logic, address _admin) TransparentUpgradeableProxy(_logic, _admin, "") {}

}
