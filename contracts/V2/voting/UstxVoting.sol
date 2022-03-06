// Staking.sol
// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

import "./IStaking.sol";
import "./IERC20.sol";
import "./Roles.sol";


/// @title Up Stable Token eXperiment Staking contract
/// @author USTX Team
/// @dev This contract implements the interswap (USTX DEX <-> SunSwap) functionality for the USTX token.
// solhint-disable-next-line
contract UstxStaking {
	using Roles for Roles.Role;

	/***********************************|
	|        Variables && Events        |
	|__________________________________*/


	//Variables
	bool private _notEntered;			//reentrancyguard state
	Roles.Role private _administrators;
	uint256 private _numAdmins;
	uint256 private _minAdmins;

    IStaking public stakingContract;

    // Info of each proposition.
    struct PropInfo {
        uint256 totalVotes;         // Total votes available, including team
        uint256 teamVotes;          // Team votes
        uint256 quorum;             // Minimum votes to be valid
        uint8 propType;           // Proposition type: 1 (yes/no), 2-5 multiple choice
        uint256 startTime;
        uint256 endTime;
        uint8 teamVoted;
        mapping (uint8 => uint256) castVotes;       // Cast votes for each possible propType
        mapping (address => uint8) hasVoted;       // 0-1 if user has voted
    }
    mapping (uint256 => PropInfo) private _propInfo;           //Proposition information
    uint256 public propIndex;

    uint256 public teamShare;          //percentage of votes assigned to the team
    uint256 private _voteLot;           //number of USTX each vote
    uint256 private _showResultsDuring;     //show voting result during voting session

	// Events
    event AdminAdded(address indexed account);
    event AdminRemoved(address indexed account);
    event PropCreated(uint256 indexed propID, uint8 indexed propType, uint256 indexed startTime, uint256 endTime, uint256 quorum);
    event PropEdited(uint256 indexed propID, uint8 indexed propType, uint256 indexed startTime, uint256 endTime, uint256 quorum);
    event Voted(uint256 indexed propID);

	/**
	* @dev costructor
	*
	*/
    constructor() {
        _notEntered = true;
        _numAdmins=0;
		_addAdmin(msg.sender);		//default admin
		_minAdmins = 2;					//at least 2 admins in charge
        propIndex = 0;
        teamShare = 20;                 //20% of total available votes are team
        _voteLot=1000000000;                  //amount of USTX per vote
        _showResultsDuring=1;           //if 1 it allows seing the voting results during voting
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

	/***********************************|
	|        ReentrancyGuard            |
	|__________________________________*/

	/**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_notEntered, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _notEntered = false;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _notEntered = true;
    }

    /* ========== VIEWS ========== */

    function totalVotes() public view returns (uint256) {
        uint256 S0;
        uint256 S1;
        uint256 S2;
        uint256 S3;
        uint256 S4;

        (S0, S1, S2, S3, S4) = stakingContract.totalStaked();

        return (S0+S1+S2+S3+S4)/_voteLot;
    }

    function userVotes(address user) public view returns (uint256) {
        uint256 S0;
        uint256 S1;
        uint256 S2;
        uint256 S3;
        uint256 S4;

        (S0, S1, S2, S3, S4) = stakingContract.balanceOf(user);

        return (S0+S1+S2+S3+S4)/_voteLot;
    }

    function userVoted(uint256 propID) public view returns (uint256){
        return(_propInfo[propID].hasVoted[msg.sender]);
    }

    function myVotes() public view returns (uint256) {
        return userVotes(msg.sender);
    }

   /**
	* @dev Function to get voting status
	* @param propID proposition ID
    * returns status: 0 pending, 1 live, 2 ended
    * returns total eligible votes
    * returns votes cast so far
    * returns if quorum is reached
	*/
    function getPropStatus(uint256 propID) public view returns (uint256, uint256, uint256, uint256) {
        uint256 status=0;         //waiting start
        uint256 votes;
        uint256 quorum=0;

        if (block.timestamp>_propInfo[propID].startTime) {
            status=1;             //voting is live
        }
        if (block.timestamp>_propInfo[propID].endTime) {
            status=2;             //voting ended
        }

        votes = _propInfo[propID].castVotes[0]+
            _propInfo[propID].castVotes[1]+
            _propInfo[propID].castVotes[2]+
            _propInfo[propID].castVotes[3]+
            _propInfo[propID].castVotes[4];

        if (votes > _propInfo[propID].quorum) {
            quorum = 1;
        }

        return (status, _propInfo[propID].totalVotes, votes, quorum);
    }

   /**
	* @dev Function to get proposition info
	* @param propID proposition ID
    * returns proposition type
    * returns start time
    * returns end time
    * returns total votes
    * returns quorum value
	*/
    function getPropInfo(uint256 propID) public view returns (uint256, uint256, uint256, uint256, uint256) {
        return (_propInfo[propID].propType,
            _propInfo[propID].startTime,
            _propInfo[propID].endTime,
            _propInfo[propID].totalVotes,
            _propInfo[propID].quorum);
    }

   /**
	* @dev Function to get voting status
	* @param propID proposition ID
    * returns votes cast so far
	*/
    function getVoteResult(uint256 propID) public view returns (uint256, uint256, uint256, uint256, uint256) {
        if (_propInfo[propID].endTime>block.timestamp || (_showResultsDuring>0 && _propInfo[propID].hasVoted[msg.sender]>0)) {
            return (_propInfo[propID].castVotes[0],
                _propInfo[propID].castVotes[1],
                _propInfo[propID].castVotes[2],
                _propInfo[propID].castVotes[3],
                _propInfo[propID].castVotes[4]);
        } else {
            return (0,0,0,0,0);
        }
    }

    /* ========== VOTING FUNCTIONS ========== */
    function voteSimple(uint256 propID, uint256 yesVotes, uint256 noVotes) public nonReentrant {
        require(_propInfo[propID].propType==1,"WRONG PROPOSITION TYPE");
        require((yesVotes==0 && noVotes !=0) || (yesVotes!=0 && noVotes ==0),"INVALID VOTE");
        require(_propInfo[propID].startTime>block.timestamp && _propInfo[propID].endTime<block.timestamp, "VOTING IS CLOSED");
        require(yesVotes+noVotes <= userVotes(msg.sender),"VOTES EXCEED BALANCE");
        require(_propInfo[propID].hasVoted[msg.sender]==0,"USER HAS ALREADY VOTED");

        PropInfo storage info = _propInfo[propID];

        info.castVotes[0] += yesVotes;
        info.castVotes[1] += noVotes;
        info.hasVoted[msg.sender] = 1;

        emit Voted(propID);
    }

    function voteSimpleTeam(uint256 propID, uint256 yesVotes, uint256 noVotes) public onlyAdmin nonReentrant {
        require(_propInfo[propID].propType==1,"WRONG PROPOSITION TYPE");
        require((yesVotes==0 && noVotes !=0) || (yesVotes!=0 && noVotes ==0),"INVALID VOTE");
        require(_propInfo[propID].startTime>block.timestamp && _propInfo[propID].endTime<block.timestamp, "VOTING IS CLOSED");
        require(yesVotes+noVotes <= _propInfo[propID].teamVotes,"VOTES EXCEED BALANCE");
        require(_propInfo[propID].teamVoted==0,"USER HAS ALREADY VOTED");

        PropInfo storage info = _propInfo[propID];

        info.castVotes[0] += yesVotes;
        info.castVotes[1] += noVotes;
        info.teamVoted = 1;

        emit Voted(propID);
    }

    function voteMulti(uint256 propID, uint256 opt0, uint256 opt1, uint256 opt2, uint256 opt3, uint256 opt4) public nonReentrant {
        require(_propInfo[propID].propType>1,"WRONG PROPOSITION TYPE");
        require(opt0>0 || opt1>0 || opt2>0 || opt3>0 || opt4>0,"INVALID VOTE");
        require(_propInfo[propID].startTime>block.timestamp && _propInfo[propID].endTime<block.timestamp, "VOTING IS CLOSED");
        require(opt0+opt1+opt2+opt3+opt4 <= userVotes(msg.sender),"VOTES EXCEED BALANCE");
        require(_propInfo[propID].hasVoted[msg.sender]==0,"USER HAS ALREADY VOTED");

        PropInfo storage info = _propInfo[propID];

        info.castVotes[0] += opt0;
        info.castVotes[1] += opt1;
        info.castVotes[2] += opt2;
        info.castVotes[3] += opt3;
        info.castVotes[4] += opt4;
        info.hasVoted[msg.sender] = 1;

        emit Voted(propID);
    }

    function voteMultiTeam(uint256 propID, uint256 opt0, uint256 opt1, uint256 opt2, uint256 opt3, uint256 opt4) public onlyAdmin nonReentrant {
        require(_propInfo[propID].propType>1,"WRONG PROPOSITION TYPE");
        require(opt0>0 || opt1>0 || opt2>0 || opt3>0 || opt4>0,"INVALID VOTE");
        require(_propInfo[propID].startTime>block.timestamp && _propInfo[propID].endTime<block.timestamp, "VOTING IS CLOSED");
        require(opt0+opt1+opt2+opt3+opt4 <= _propInfo[propID].teamVotes,"VOTES EXCEED BALANCE");
        require(_propInfo[propID].teamVoted==0,"USER HAS ALREADY VOTED");

        PropInfo storage info = _propInfo[propID];

        info.castVotes[0] += opt0;
        info.castVotes[1] += opt1;
        info.castVotes[2] += opt2;
        info.castVotes[3] += opt3;
        info.castVotes[4] += opt4;
        info.teamVoted = 1;

        emit Voted(propID);
    }
    /* ========== RESTRICTED FUNCTIONS ========== */

    function newProposition(uint8 propType, uint256 start, uint256 end, uint256 qPerc) public onlyAdmin {
        require(propType<6,"WRONG PROPOSITION TYPE");
        require(start>block.timestamp && end>block.timestamp,"CHECK START AND END TIMES");

        uint256 total = totalVotes();
        uint256 team = total*teamShare/100;
        total += team;       //add team share to total votes;

        PropInfo storage info = _propInfo[propIndex];
        info.totalVotes = total;
        info.teamVotes = team;
        info.quorum = total*qPerc/100;
        info.propType = propType;
        info.startTime = start;
        info.endTime = end;
        info.teamVoted = 0;

        emit PropCreated(propIndex, propType, start, end, qPerc);
        propIndex++;
    }

    function editProposition(uint256 propID, uint8 propType, uint256 start, uint256 end, uint256 qPerc) public onlyAdmin {
        require(propType<6,"WRONG PROPOSITION TYPE");
        require(start>block.timestamp && end>block.timestamp,"CHECK START AND END TIMES");
        require(propID<propIndex,"PROPOSITION DOES NOT EXIST");

        PropInfo storage info = _propInfo[propID];
        info.quorum = info.totalVotes*qPerc/100;
        info.propType = propType;
        info.startTime = start;
        info.endTime = end;

        emit PropEdited(propID, propType, start, end, qPerc);
    }

    function setVoteLot(uint256 newLot) public onlyAdmin {
        require(newLot>0,"INVALID LOT NUMBER");
        _voteLot = newLot;
    }

    function setResultsVisibility(uint256 allowDuring) public onlyAdmin {
        _showResultsDuring = allowDuring;
    }

    function setTeamShare(uint256 share) public onlyAdmin {
        require(share<25,"TEAM SHARE CANNOT BE BIGGER THAN 25%");
        teamShare = share;
    }

	/**
	* @dev Function to set Stake contract address (only admin)
	* @param contractAddress address of the traded token contract
	*/
	function setStakingAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		stakingContract = IStaking(contractAddress);
	}

    /**
	* @dev Function to withdraw lost tokens balance (only admin)
	* @param tokenAddr Token address
	*/
	function withdrawToken(address tokenAddr) public onlyAdmin returns(uint256) {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");

		IERC20 token = IERC20(tokenAddr);

		uint256 balance = token.balanceOf(address(this));

		token.transfer(msg.sender,balance);

		return balance;
	}

	/**
	* @dev Function to withdraw TRX balance (only admin)
	*/
    function withdrawTrx() public onlyAdmin returns(uint256){
        uint256 balance = address(this).balance;
		address payable rec = payable(msg.sender);
		(bool sent, ) = rec.call{value: balance}("");
		require(sent, "Failed to send TRX");
		return balance;
    }

}
