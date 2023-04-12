// ErgonRelay.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Roles.sol";


interface IErgon {
   function borrowEnergy(address user, uint256 trxToDelegate, uint256 duration, uint256 ts, uint8 v, bytes32 r, bytes32 s) payable external;
}

contract ErgonRelay {
    using Roles for Roles.Role;

	Roles.Role private _administrators;
	uint256 private _numAdmins;
	uint256 private _minAdmins;

	IErgon public ergonContract;

	uint256 public freeEnergyLimit;

    event AdminAdded(address account);
    event AdminRemoved(address account);

    constructor() {
        _numAdmins=0;
		_addAdmin(msg.sender);		//default admin
		_minAdmins = 1;					//at least 1 admins in charge

		freeEnergyLimit = 500000;
    }

	/***********************************|
	|        AdminRole                  |
	|__________________________________*/

	modifier onlyAdmin() {
        require(isAdmin(msg.sender), "AdminRole: caller does not have the Admin role");
        _;
    }

    function isAdmin(address account) public view returns (bool) {
        return _administrators.has(account);
    }

    function addAdmin(address account) public onlyAdmin {
        _addAdmin(account);
    }

    function renounceAdmin() public {
        require(_numAdmins>_minAdmins, "There must always be a minimum number of admins in charge");
        _removeAdmin(msg.sender);
    }

    function _addAdmin(address account) internal {
        _administrators.add(account);
        _numAdmins++;
        emit AdminAdded(account);
    }

    function _removeAdmin(address account) internal {
        _administrators.remove(account);
        _numAdmins--;
        emit AdminRemoved(account);
    }

    function trxToEnergy(uint256 trxAmount) internal view returns(uint256){
        return (chain.totalEnergyCurrentLimit * trxAmount / chain.totalEnergyWeight / 1e6);
    }

    function borrowEnergy(address user, uint256 trxToDelegate, uint256 duration, uint256 ts, uint8 v, bytes32 r, bytes32 s) payable public {
        require(trxToEnergy(trxToDelegate) < freeEnergyLimit, "Order too big");

        ergonContract.borrowEnergy{value: msg.value}(user, trxToDelegate, duration, ts, v, r, s);
    }

    function setErgonAddr(address account) public onlyAdmin {
	    require(account != address(0), "INVALID_ADDRESS");
		ergonContract = IErgon(account);
	}

    function setFreeLimit(uint256 limit) public onlyAdmin {
		freeEnergyLimit = limit;
	}
}
