// FairLaunch.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.5;

import "./Roles.sol";
import "./IERC20.sol";

contract FairLuckPad {
    using Roles for Roles.Role;

    bool private _notEntered;			//reentrancyguard state
	Roles.Role private _administrators;

    address public launchToken;         //launch token
    address public treasury;            //treasury address
    uint256 public softCap;             //minimum BTT to be raised for a valid launch
    uint256 public totalRaised;         //total BTT raised
    uint256 public totalRaisedLuck;     //total BTT raised factorizing luck
    uint256 public treasuryPerc;        //treasury percentage of raised money (10)
    uint256 public totalRedeem;         //total redeemed
    uint256 public startTime;           //launch start
    uint256 public duration;            //total duration in seconds (2*86400)
    bool public saleEnabled;            //enable launch
    bool public redeemEnabled;          //redeem enabled
    bool public setup;                  //liquidity setup status
    uint256 public maxInvest;           //max BTT to invest
    uint256 public numInvested;         //numner of launch customers
    uint256 public reedemRatio;         //ratio of tokens to BTT
    uint256 public treasuryShare;       //tokens allocated to treasury (10% of total)
    uint256 public lpShare;             //tokens allocated to LPs
    uint256 public launchShare;         //tokens aloocated to users

    event SaleEnabled(bool enabled, uint256 time);
    event RedeemEnabled(bool enabled, uint256 time);
    event Invest(address investor, uint256 amount);
    event Redeem(address investor, uint256 amount);
    event AdminAdded(address account);
    event AdminRemoved(address account);

    struct InvestorInfo {
        uint256 amountInvested;         // BTT deposited by user
        uint256 luckFactor;             // How lucky was the user (100->200)
        bool claimed;                   // token has been claimed
    }

    mapping(address => InvestorInfo) public investors;

    constructor() {
        _notEntered = true;
		_addAdmin(msg.sender);		//default admin
        duration = 24*3600;         //1 day
        softCap = 5000000000 * 10**18;           //5B BTT
        maxInvest = 2000000000 * 10**18;         //2B BTT
        redeemEnabled = false;
        saleEnabled = false;
        treasuryPerc = 25;          //25%
        minLuck = 100;            //base luck: 100%
        maxLuck = 200;            //max luck: 200%
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
        _removeAdmin(msg.sender);
    }

    function _addAdmin(address account) internal {
        _administrators.add(account);
        emit AdminAdded(account);
    }

    function _removeAdmin(address account) internal {
        _administrators.remove(account);
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

    function getCap() public view returns(uint256){
        return (totalRaised * 100 / softCap);
    }

    // invest
    function invest() public payable nonReentrant{
        require(block.timestamp >= startTime, "not started yet");
        require(block.timestamp < startTime+duration, "sale ended");
        require(saleEnabled, "not enabled yet");

        InvestorInfo storage investor = investors[msg.sender];

        require(investor.amountInvested + msg.value <= maxInvest, "investment too high");

        totalRaised += msg.value;

        uint256 userLuck = getLuck(msg.sender);   //luck function tbd

        if (investor.amountInvested == 0){
            numInvested += 1;
        }
        investor.amountInvested += msg.value;
        investor.luckFactor = userLuck;     //fix for multiple additions

        totalRaisedLuck += msg.value * userLuck / 100;s

        emit Invest(msg.sender, msg.value);
    }

    // claim tokens
    function redeem() public nonReentrant {
        require(redeemEnabled, "redeem not enabled");
        InvestorInfo storage investor = investors[msg.sender];
        uint256 redeemAmount = investor.amountInvested * reedemRatio / 10**9;
        require(redeemAmount > 0, "nothing to claim");
        require(!investor.claimed, "already claimed");
        if (getCap()>=100) {                        //launch success, send tokens
            require(
                IERC20(launchToken).transfer(
                    msg.sender,
                    redeemAmount
                ),
                "Failed to send tokens"
            );
        } else {                                    //launch failed, return BTT
            address payable rec = payable(msg.sender);
            (bool sent, ) = rec.call{value: investor.amountInvested}("");
            require(sent, "Failed to send BTT");
        }

        totalRedeem += investor.amountInvested;
        emit Redeem(msg.sender, investor.amountInvested);
        investor.claimed = true;
    }

    // define the launch token to be redeemed
    function setLaunchToken(address _launchToken) public onlyAdmin {
        launchToken = _launchToken;
    }

    // define the treasury address
    function setTreasuryAddress(address _treasury) public onlyAdmin {
        treasury = _treasury;
    }

    // withdraw in case some tokens were not redeemed
    function withdrawLaunchtoken(uint256 amount) public onlyAdmin {
        require(launchToken != address(0), "launch token not set");
        require(block.timestamp > startTime + duration + 7*24*3600, "tokens still locked");
        require(
            IERC20(launchToken).transfer(msg.sender, amount),
            "Failed to send tokens"
        );
    }

    // setup liquidity into launch contract
    function setupLiquidity(uint256 amount) public onlyAdmin returns(uint256 team, uint256 lp, uint256 launch) {
        require(amount>0, "Amount cannot be zero");
        require(launchToken != address(0), "launch token not set");
        require(
            IERC20(launchToken).transferFrom(msg.sender, address(this), amount),
            "Failed to transfer tokens"
        );

        team = amount * treasuryPerc / 100;             //team share
        treasuryShare += team;                              //incremental
        amount -= team;

        lp = amount * (100 - treasuryPerc) / (200 - treasuryPerc);   //launch share
        launch = amount - lp;                           //LP share

        launchShare += launch;                          //incremental
        lpShare += lp;                                  //incremental

        setup = true;
        return(team, lp, launch);
    }

    // preview setup liquidity into launch contract
    function previewSetupLiquidity(uint256 amount) public view returns(uint256 team, uint256 lp, uint256 launch) {
        team = amount * treasuryPerc / 100;             //team share

        amount -= team;

        lp = amount * (100 - treasuryPerc) / (200 - treasuryPerc);   //launch share
        launch = amount - lp;                           //LP share

        return(team, lp, launch);
    }

    // transfer liquidity to treasury and LP
    function distributeLiquidity() public onlyAdmin {
        require(setup, "liquidity not setup");
        require(launchToken != address(0), "launch token not set");
        require(getCap()>=100, "launch failed, BTT returns to users");
        require(block.timestamp > startTime + duration, "sale not ended yet");
        uint256 amount=totalRaised * treasuryPerc / 100;

        address payable rec = payable(treasury);
		(bool sent, ) = rec.call{value: amount}("");
		require(sent, "Failed to send BTT to treasury");

        rec = payable(msg.sender);
		(sent, ) = rec.call{value: totalRaised-amount}("");
		require(sent, "Failed to send BTT to LP");

        require(
            IERC20(launchToken).transfer(msg.sender, lpShare),
            "Failed to send tokens to LP"
        );
    }

    //claim vested treasury tokens
    function claimTreasury() public onlyAdmin {
        require(launchToken != address(0), "launch token not set");
        require(block.timestamp > startTime + duration, "tokens still locked");
        require(treasuryShare>0, "no tokens to redeem");

        require(
            IERC20(launchToken).transfer(treasury, treasuryShare),
            "Failed to send tokens to Treasury"
        );
    }

    function enableSale() public onlyAdmin {
        require(startTime>0, "start time not set");
        require(duration>0, "duration not set");
        saleEnabled = true;
        emit SaleEnabled(true, block.timestamp);
    }

    function enableRedeem() public onlyAdmin {
        require(launchToken != address(0), "launch token not set");
        require(block.timestamp > startTime+duration, "sale not ended yet");
        require(setup, "liquidity not setup");
        redeemEnabled = true;
        reedemRatio = launchShare * 10**9 / totalRaisedLuck;    //check
        emit RedeemEnabled(true, block.timestamp);
    }

    function previewRedeem() public view returns(uint256 ratio){
        ratio = launchShare * 10**9 / totalRaisedLuck;
        return ratio;
    }

    function setSoftCap(uint256 _cap) public onlyAdmin {
        softCap = _cap;
    }

    function setDuration(uint256 _hours) public onlyAdmin {
        duration = _hours * 3600;
    }

    function setStart(uint256 _start) public onlyAdmin {
        startTime = _start;
    }

    function setMax(uint256 _max) public onlyAdmin {
        maxInvest = _max;
    }

    function getTiming() public view returns(uint256 timeToStart, uint256 timeToEnd, uint256 start, uint256 end){
        if (block.timestamp < startTime){
            timeToStart = startTime - block.timestamp;
        } else {
            timeToStart = 0;
        }

        if (block.timestamp < startTime + duration){
            timeToEnd = startTime + duration - block.timestamp;
        } else {
            timeToEnd = 0;
        }
        return(timeToStart, timeToEnd, startTime, startTime + duration);
    }

    function getUserInfo(address user) public view returns(uint256 amount, bool claimed, uint256 share, uint256 tokens){
        if (totalRaised > 0) {
            share = investors[user].amountInvested * 1000 * investors[user].luckFactor / totalRaisedLuck / 100;
            tokens = investors[user].amountInvested * launchShare * investors[user].luckFactor / totalRaisedLuck / 100;
        }

        return(investors[user].amountInvested, investors[user].claimed, share, tokens);
    }
}
