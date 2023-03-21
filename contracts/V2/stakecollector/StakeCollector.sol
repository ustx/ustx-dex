// Staking.sol
// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

import "./Roles.sol";


interface IStakingV1 {
    function balanceOf(address account) external view returns (uint256, uint256, uint256, uint256, uint256);

    function totalStaked() external view returns (uint256, uint256, uint256, uint256, uint256);
}

interface IStakingV2 {
    function balanceOf(address account) external view returns (uint256, uint256);

    function totalStaked() external view returns (uint256, uint256);
}

/// @title Up Stable Token eXperiment Staking contract
/// @author USTX Team
/// @dev This contract implements the interswap (USTX DEX <-> SunSwap) functionality for the USTX token.
// solhint-disable-next-line
contract StakeCollector {
    using Roles for Roles.Role;

	Roles.Role private _administrators;
	uint256 private _numAdmins;
	uint256 private _minAdmins;

	IStakingV1 public stakingContractV1;
    IStakingV2 public stakingContractV2;

    event AdminAdded(address account);
    event AdminRemoved(address account);

    constructor() {
        _numAdmins=0;
		_addAdmin(msg.sender);		//default admin
		_minAdmins = 1;					//at least 2 admins in charge

		stakingContractV1 = IStakingV1(address(0));
		stakingContractV2 = IStakingV2(address(0));
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

    function _totalStaked() public view returns (uint256) {
        uint256 totalS1 = 0;
        uint256 totalS2 = 0;

        uint256 S0;
        uint256 S1;
        uint256 S2;
        uint256 S3;
        uint256 S4;

        if (address(stakingContractV1) != address(0)) {
            (S0, S1, S2, S3, S4) = stakingContractV1.totalStaked();
            totalS1 = S0+S1+S2+S3+S4;
        }

        if (address(stakingContractV2) != address(0)) {
            (S0, S1) = stakingContractV2.totalStaked();
            totalS2 = S0+S1;
        }
        return (totalS1+totalS2);
    }

    function balanceOf(address account) public view returns (uint256, uint256, uint256,uint256, uint256){
        uint256 S2_0 = 0;
        uint256 S2_2 = 0;

        uint256 S0;
        uint256 S1;
        uint256 S2;
        uint256 S3;
        uint256 S4;

        if (address(stakingContractV1) != address(0)) {
            (S0, S1, S2, S3, S4) = stakingContractV1.balanceOf(account);
        }

        if (address(stakingContractV2) != address(0)) {
            (S2_0, S2_2) = stakingContractV2.balanceOf(account);
        }
        return (S0+S2_0,S1,S2+S2_2,S3,S4);
    }

    function setStakingV1Addr(address contractAddress) public onlyAdmin {
		stakingContractV1 = IStakingV1(contractAddress);
	}

    function setStakingV2Addr(address contractAddress) public onlyAdmin {
		stakingContractV2 = IStakingV2(contractAddress);
	}
}
