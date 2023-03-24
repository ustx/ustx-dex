// TBoost.sol
// SPDX-License-Identifier: MIT
// solhint-disable-next-line
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./ISunSwap.sol";
import "./IStableSwap2P.sol";
import "./IJToken.sol";
import "./IJTRX.sol";
import "./IComptroller.sol";
import "./IFarm.sol";
import "./IRewards.sol";
import "./IDex.sol";
import "./Roles.sol";
import "./Initializable.sol";
import "./IMerkleDistributor.sol";

/// @title Up Stable Token eXperiment T-Boost contract (V2)
/// @author USTX Team
/// @dev This contract implements the T-Bost app
contract TBoostV2 is Initializable{
	using Roles for Roles.Role;

	/***********************************|
	|        Variables && Events        |
	|__________________________________*/


	//Variables
	bool private _notEntered;			//reentrancyguard state
	Roles.Role private _administrators;
	uint256 private _numAdmins;
	uint256 private _minAdmins;

    IERC20 public usddToken;
    IERC20 public usdtToken;
    IERC20 public sunToken;
    IERC20 public jstToken;
    IERC20 public ssUsddTrxToken;
    IERC20 public ustxToken;
    IStableSwap2P public stableSwapContract;
    ISunSwap public ssUsddTrxContract;
    ISunSwap public ssJstTrxContract;
    ISunSwap public ssSunTrxContract;
    IFarm public farmTrxUsddContract;
    IRewards public farmRewardsContract;
    IComptroller public justLendContract;
    IJToken public jUsddToken;
    IJToken public jUsdtToken;
    IJTRX public jTrxToken;
    IDex public ustxDex;


    uint256 public currentEpoch;

    uint256 private _totalDeposits;

    uint256 private _totalRewards;
    uint256 private _paidRewards;
    uint256 private _totalPendingWithdraw;

    uint256 private _lockDuration;

    uint256 private _depositEnable;
    uint256 private _maxPerAccount;
    uint256 private _maxTotal;
    uint256 public userRewardPerc;
    uint256 public buybackRewardPerc;
    address public buybackAccount;
    uint256 public safetyMargin;
    uint256 public lpRatio;
    uint256 public lastAPR;

    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _lastUpdate;
    mapping(address => uint256) private _rewards;
    mapping(address => uint256) private _withdrawLock;
    mapping(address => uint256) private _pendingWithdraw;
    mapping(uint256 => uint256) private _rewardRates;

    //Last V1 variable
    uint256 private _version;

    //V2 Variables
    IMerkleDistributor public jlDistributorContract;

	// Events
    event NewEpoch(uint256 epoch, uint256 reward, uint256 rate);
    event Deposit(address user, uint256 amount);
    event Withdraw(address user, uint256 amount);
    event RewardPaid(address user, uint256 reward);
    event AdminAdded(address account);
    event AdminRemoved(address account);
    event TrxReceived(uint256 amount);

	/**
	* @dev initializer
	*
	*/
    function initialize() public initializer {
    //constructor () {
        _notEntered = true;
        _version=1;
        _numAdmins=0;
		_addAdmin(msg.sender);		//default admin
		_minAdmins = 2;					//at least 2 admins in charge
        currentEpoch = 1;
        _totalRewards = 0;
        _paidRewards = 0;
        _lockDuration = 1;  //1 epoch lock
        _depositEnable=1;
        _maxPerAccount = 100000000000;     //100,000 TRX per account
        _maxTotal = 10000000000000;      //10,000,000 TRX in total
        userRewardPerc = 75;           //user share of the rewards
        buybackRewardPerc = 20;        //buyback share of the rewards
        safetyMargin = 20;              //20% margine required to withdraw
        lpRatio = 55;              //55% goes  to LP
        usddToken = IERC20(0x94F24E992cA04B49C6f2a2753076Ef8938eD4daa);     //USDD
        usdtToken = IERC20(0xa614f803B6FD780986A42c78Ec9c7f77e6DeD13C);     //USDT
        sunToken = IERC20(0xb4A428ab7092c2f1395f376cE297033B3bB446C1);      //Sun
        jstToken = IERC20(0x18FD0626DAF3Af02389AEf3ED87dB9C33F638ffa);      //Just
        ustxToken = IERC20(0xf7577FB404641Cf7DCd6b0708CFcA49732abf9b3);     //USTX
        ssUsddTrxToken = IERC20(0xb3289906AD9381cb2D891DFf19A053181C53b99D);    //S-USDD-TRX
        stableSwapContract = IStableSwap2P(0x8903573F4c59704f3800E697Ac333D119D142Da9);     //StableSwap 2 pool
        ssUsddTrxContract = ISunSwap(0xb3289906AD9381cb2D891DFf19A053181C53b99D);           //SunSwap TRX-USDD
        ssJstTrxContract = ISunSwap(0xFBa3416f7aaC8Ea9E12b950914d592c15c884372);            //SunSwap TRX-JST
        ssSunTrxContract = ISunSwap(0x25B4c393a47b2dD94D309F2ef147852Deff4289D);            //SunSwap TRX-SUN
        jUsddToken = IJToken(0xE7F8A90ede3d84c7c0166BD84A4635E4675aCcfC);                   //jUSDD
        jUsdtToken = IJToken(0xea09611b57e89d67FBB33A516eB90508Ca95a3e5);                   //jUSDT
        jTrxToken = IJTRX(0x2C7c9963111905d29eB8Da37d28b0F53A7bB5c28);                      //jTRX
        justLendContract = IComptroller(0x4a33BF2666F2e75f3D6Ad3b9ad316685D5C668D4);        //JustLend Comptroller
        farmTrxUsddContract = IFarm(0x1F446B0225e73BBBe18d83A91a35Ef2b372df6C8);            //USDD-TRX farm
        farmRewardsContract = IRewards(0xa72bEF5581ED09d848ca4380ede64192978b51b9);         //USDD rewards contract
        buybackAccount = address(0x59b172a17666224C6AeE90b58b20E686d47d9267);               //Buyback account
        ustxDex = IDex(0x82D4553256514373f0FACbF841e43D1080dbdE73);                         //USTX DEX
    }

	/**
	* @dev upgrade function for V2
	*/
	function upgradeToV2() public onlyAdmin {
        require(_version < 2,"Contract already up to date");
        _version=2;

        jlDistributorContract = IMerkleDistributor(0xa2bE60D047EeE7ABEb6C1dA51430eD7Ffe45E67D);
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

    // ========== FALLBACK ==========

    receive() external payable {
        emit TrxReceived(msg.value);
    }

    /* ========== VIEWS ========== */

    function totalStaked() public view returns (uint256) {
        return (_totalDeposits);
    }

    function getBalances() public view returns(uint256, uint256, uint256, uint256) {
        return (address(this).balance, _totalDeposits + _totalPendingWithdraw, ustxToken.balanceOf(address(this)), _totalRewards-_paidRewards);
    }

    function allRewards() public view returns (uint256,uint256,uint256) {
        return (_totalRewards, _paidRewards, _totalRewards-_paidRewards);       //total, paid, pending
    }

    function balanceOf(address account) public view returns (uint256, uint256) {
        return (_balances[account], _pendingWithdraw[account]);
    }

    function lastUpdate(address account) public view returns (uint256) {
        return (_lastUpdate[account]);
    }

    function getEnable() public view returns (uint256) {
        return (_depositEnable);
    }

    function earned(address account) public view returns (uint256) {
        uint256 temp=0;
        uint256 reward=0;
        uint256 i;

        for (i=_lastUpdate[account];i<currentEpoch;i++) {
            temp += _rewardRates[i];      //changed
        }
        reward = _rewards[account] + temp*_balances[account]/1e18;

        return (reward);
    }

    function getBaseAPY(uint256 epoch) public view returns (uint256) {
        return (_rewardRates[epoch]);
    }

    function getLock(address account) public view returns (uint256) {
        uint256 lock1 = 0;

        if (currentEpoch <= _withdrawLock[account]) {
            lock1 = _withdrawLock[account]-currentEpoch + 1;
        }

        return (lock1);
    }

    function getLimits() public view returns (uint256, uint256) {
        return (_maxPerAccount, _maxTotal);
    }

    function getAvailableLimits(address account) public view returns (uint256, uint256){
        uint256 totAvailable = 0;
        uint256 userAvailable = 0;

        if (_maxTotal > _totalDeposits) {
            totAvailable = _maxTotal - _totalDeposits;
        }

        if (_maxPerAccount > _balances[account]) {
            userAvailable = _maxPerAccount - _balances[account];
        }
        return (totAvailable, userAvailable);
    }

    /* ========== DEPOSIT FUNCTIONS ========== */

    function depositAndSupply() public payable nonReentrant updateReward(msg.sender) {
        require(msg.value > 0, "Cannot stake 0");
        require(_depositEnable > 0, "Deposits not allowed");
        require(_balances[msg.sender] + msg.value < _maxPerAccount, "User maximum allocation reached");
        require(_totalDeposits + msg.value < _maxTotal, "Total maximum allocation reached");

        _totalDeposits += msg.value;
        _balances[msg.sender] += msg.value;

        uint256 toSupply = msg.value*(100-lpRatio/2)/100;           //70% if lpRatio == 60

        jTrxToken.mint{value: toSupply}();                            //supply new liquidity to JL

        emit Deposit(msg.sender, msg.value);
    }

    /* ========== COMPOUND FUNCTION ========== */
    // Cannot compound USTX with TRX

    /* ========== WITHDRAW FUNCTIONS ========== */
    function bookWithdraw(uint256 amount) public nonReentrant updateReward(msg.sender) returns(uint256){
        require(amount > 0, "Cannot withdraw 0");
        require(amount <= _balances[msg.sender], "Amount exceeds balance");

        _withdrawLock[msg.sender]=currentEpoch + _lockDuration;        //set unlock time

        (uint256 ratio,,) = getEquityRatio();

        _balances[msg.sender] -= amount;
        _totalDeposits -= amount;

        if (ratio<1000) {
            amount=amount*ratio/1000;           //if capital is not covering 100% of the deposits
        }
        _pendingWithdraw[msg.sender] += amount;              //move amount from active deposits to pending
        _totalPendingWithdraw += amount;

        return (amount);
    }

    function withdrawPending() public nonReentrant {
        require(_pendingWithdraw[msg.sender]>0, "Nothing to withdraw");
        require(currentEpoch > _withdrawLock[msg.sender], "Funds locked");

        uint256 temp = _pendingWithdraw[msg.sender];
        _totalPendingWithdraw -= temp;
        _pendingWithdraw[msg.sender] = 0;
        _withdrawLock[msg.sender]=currentEpoch + 5200;        //re-lock account

        (,uint256 margin,) = getAccountLiquidity();
        (,uint256 trxSupply,,uint256 trxRate) = jTrxToken.getAccountSnapshot(address(this));
        trxSupply = trxSupply*trxRate/10**18;

        require(margin-temp > trxSupply / safetyMargin, "INSUFFICIENT MARGIN ON JL");     //keep at least 20% margin after withdrawal
        jTrxToken.redeemUnderlying(temp);

        address payable rec = payable(msg.sender);
		(bool sent, ) = rec.call{value: temp}("");
		require(sent, "Failed to send TRX");

        emit Withdraw(msg.sender, temp);
    }

    /* ========== REWARDS FUNCTIONS ========== */

    function getReward() public nonReentrant updateReward(msg.sender) returns(uint256){
        require(_rewards[msg.sender]>0, "No rewards for user");
        uint256 reward = _rewards[msg.sender];

        _paidRewards += reward;
        _rewards[msg.sender] = 0;
        ustxToken.transfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);

        return reward;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function newEpochPreview(uint256 usddEpochRewards) public view returns(uint256, uint256, uint256, uint256, uint256){
        uint256 buybackRewards = usddEpochRewards*buybackRewardPerc /100;

        uint256 userRewards = usddEpochRewards*userRewardPerc/100;          //user rewards in USDD

        uint256 trxRate = getUsddValueInTrx(userRewards) * 52 * 100 * 1000/ _totalDeposits;

        userRewards = ustxDex.buyTokenInputPreview(userRewards/10**12);            //user rewards in USTX

        uint256 rate = 0;

        rate = userRewards * 1e18 / _totalDeposits;   //current epoch base rate in USTX per TRX deposited


        return (rate, trxRate, userRewards, buybackRewards, usddToken.balanceOf(address(this)));
    }

    function newEpoch(uint256 usddEpochRewards) public onlyAdmin {
        require(usddEpochRewards>0, "REWARDS MUST BE > 0");

        uint256 buybackRewards = usddEpochRewards*buybackRewardPerc /100;
        require(usddToken.balanceOf(address(this))> usddEpochRewards, "Insufficient contract balance");

        uint256 userRewards = usddEpochRewards*userRewardPerc/100;          //user rewards in USDD

        lastAPR = getUsddValueInTrx(userRewards) * 52 * 100 * 1000/ _totalDeposits;

        userRewards = ustxDex.buyTokenInput(userRewards/10**12,1,1);            //user rewards in USTX

        if (buybackRewards>0) {
            usddToken.transfer(buybackAccount, buybackRewards);
        }

        _rewardRates[currentEpoch] = userRewards * 1e18 / _totalDeposits;   //current epoch base rate in USTX per TRX deposited
        _totalRewards += userRewards;

        emit NewEpoch(currentEpoch, userRewards, _rewardRates[currentEpoch]);


        currentEpoch++;
    }

    function setLockDuration(uint256 lockWeeks) public onlyAdmin {
        require(lockWeeks < 5, "Reduce lock duration");

        _lockDuration = lockWeeks;
    }

    //
    //APPROVALS
    //

	function approveGeneric(address tokenAddr, address spender, uint256 amount) public onlyAdmin {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");
		require(spender != address(0), "INVALID_ADDRESS");

		IERC20 token = IERC20(tokenAddr);

	    token.approve(spender, amount);
	}

    function approveAll() public onlyAdmin {
        //Approve USDD to jUSDD
        usddToken.approve(address(jUsddToken), 2**256-1);

        //Approve USDD to SunSwap UsddTrx LP
        usddToken.approve(address(ssUsddTrxContract), 2**256-1);

        //Approve USDD to 2Pool
        usddToken.approve(address(stableSwapContract), 2**256-1);

        //Approve USDD to USTX DEX
        usddToken.approve(address(ustxDex), 2**256-1);

        //Approve USDT to 2Pool
        usdtToken.approve(address(stableSwapContract), 2**256-1);

        //Approve Usdt to jUsdt
        usdtToken.approve(address(jUsdtToken), 2**256-1);

        //Approve UsddTrx to Farm
        ssUsddTrxToken.approve(address(farmTrxUsddContract), 2**256-1);

        //Approve JST to SunSwap JstTrx LP
        jstToken.approve(address(ssJstTrxContract), 2**256-1);

        //Approve SUN to SunSwap SunTrx LP
        sunToken.approve(address(ssSunTrxContract), 2**256-1);
    }

    //
    // JustLend interface functions
    //

    function jlSupplyTrx(uint256 amount) public onlyAdmin returns(uint256){
        require(amount > 0, "AMOUNT_INVALID");

        uint256 jTrxMinted;

        jTrxToken.mint{value: amount}();

        return jTrxMinted;      //no value returned by the mint function
    }

    function jlEnableCollateral() public onlyAdmin {
        justLendContract.enterMarket(address(jTrxToken));
    }

    function jlWithdrawTrx(uint256 amount) public onlyAdmin returns(uint256){
        require(amount > 0, "AMOUNT_INVALID");

        uint256 ret;

        ret = jTrxToken.redeemUnderlying(amount);

        return ret;
    }

    function jlBorrowUsdt(uint256 amount) public onlyAdmin {
        require(amount > 0, "AMOUNT_INVALID");

        jUsdtToken.borrow(amount);
    }

    function jlRepayUsdt(uint256 amount) public onlyAdmin returns(uint256){
        require(amount > 0, "AMOUNT_INVALID");

        uint256 ret;

        ret = jUsdtToken.repayBorrow(amount);

        return ret;
    }

    //
    // SunSwap functions
    //

    function swapSunForUsdd() public onlyAdmin returns(uint256){
        require(sunToken.balanceOf(address(this)) > 0, "NO SUN TO SWAP");

        uint256 ret;

        ret = ssSunTrxContract.tokenToTokenSwapInput(sunToken.balanceOf(address(this)), 1, 1, block.timestamp+10, 0x94F24E992cA04B49C6f2a2753076Ef8938eD4daa);

        return ret;
    }

    function swapUsddForTrx(uint256 amount) public onlyAdmin returns(uint256){
        require(amount > 0, "AMOUNT_INVALID");

        uint256 ret;

        ret = ssUsddTrxContract.tokenToTrxSwapInput(amount, 1, block.timestamp+10);

        return ret;
    }

    function swapTrxForUsdd(uint256 amount) public onlyAdmin returns(uint256){
        require(amount > 0, "AMOUNT_INVALID");

        uint256 ret;

        ret = ssUsddTrxContract.trxToTokenSwapInput{value: amount}(1, block.timestamp+10);

        return ret;
    }

    function ssAddLiquidity(uint256 amountTrx) public onlyAdmin returns(uint256){
        require(amountTrx > 0, "AMOUNT_INVALID");

        uint256 lp;

        lp = ssUsddTrxContract.addLiquidity{value: amountTrx}(1, amountTrx*10**21, block.timestamp+60);

        return lp;
    }

    function ssRemoveLiquidity(uint256 lpAmount) public onlyAdmin returns(uint256, uint256){
        require(lpAmount > 0, "AMOUNT_INVALID");

        uint256 trxT;
        uint256 usdd;

        (trxT, usdd) = ssUsddTrxContract.removeLiquidity(lpAmount, 1,1,block.timestamp+60);

        return(trxT, usdd);
    }

    //
    //2Pool
    //

    function swapUsddForUsdt(uint256 amount) public onlyAdmin {
        require(amount > 0, "AMOUNT_INVALID");

        stableSwapContract.exchange(0,1,amount, 1);
    }

    function swapUsdtForUsdd(uint256 amount) public onlyAdmin {
        require(amount > 0, "AMOUNT_INVALID");

        stableSwapContract.exchange(1,0,amount, 1);
    }

    //
    //Farm
    //

    function farmDeposit(uint256 lpAmount) public onlyAdmin {
        require(lpAmount > 0, "AMOUNT_INVALID");

        farmTrxUsddContract.deposit(lpAmount);
    }

    function farmWithdraw(uint256 lpAmount) public onlyAdmin {
        require(lpAmount > 0, "AMOUNT_INVALID");

        farmTrxUsddContract.withdraw(lpAmount);
    }

    function farmClaim() public onlyAdmin {
        farmTrxUsddContract.claim_rewards();
        farmRewardsContract.claim(0x0000000000000000000000411f446b0225e73bbbe18d83a91a35ef2b372df6c8);
    }

    //
    // Equity view functions
    //

    function getLpUsddValue() public view returns(uint256){
        uint256 lpTotal;
        uint256 ssUsddBalance;
        uint256 lpThis;
        uint256 rewards;

        lpTotal = ssUsddTrxToken.totalSupply();
        lpThis = ssUsddTrxToken.balanceOf(address(this));
        lpThis += farmTrxUsddContract.balanceOf(address(this));
        rewards = farmTrxUsddContract.claimable_reward_for(address(this));

        ssUsddBalance = usddToken.balanceOf(address(ssUsddTrxContract));

        return ssUsddBalance * 2 * lpThis / lpTotal + rewards;
    }

    function getUsddValueInTrx(uint256 usddAmount) public view returns(uint256){
        uint256 usddBalance;
        uint256 trxBalance;

        usddBalance = usddToken.balanceOf(address(ssUsddTrxContract));
        trxBalance = address(ssUsddTrxContract).balance;

        return trxBalance * usddAmount / usddBalance;
    }

    function getTrxValueInUsdd(uint256 trxAmount) public view returns(uint256){
        uint256 usddBalance;
        uint256 trxBalance;

        usddBalance = usddToken.balanceOf(address(ssUsddTrxContract));
        trxBalance = address(ssUsddTrxContract).balance;

        return usddBalance * trxAmount / trxBalance;
    }

    function getUsdtUsddValue(uint256 usdtAmount) public view returns(uint256){
        uint256 value = 0;

        if (usdtAmount >0) {
            value = stableSwapContract.get_dy(1,0,usdtAmount);
        }
        return value;
    }

    function getEquityValue() public view returns(uint256, uint256, uint256, uint256){
        uint256 thisBal;
        uint256 usdtBor;
        uint256 lpVal;
        uint256 trxSupply;
        uint256 trxRate;

        (,,usdtBor,) = jUsdtToken.getAccountSnapshot(address(this));

        usdtBor = getUsdtUsddValue(usdtBor);
        usdtBor = getUsddValueInTrx(usdtBor);       //Borrowed USDT value in TRX

        thisBal = getUsddValueInTrx(usddToken.balanceOf(address(this)));                        //account balance value in USDD
        thisBal += getUsddValueInTrx(getUsdtUsddValue(usdtToken.balanceOf(address(this))));     //avvount balance in USDT
        thisBal += address(this).balance;                                                       //account balance in TRX

        lpVal = getLpUsddValue();
        lpVal= getUsddValueInTrx(lpVal);
        (,trxSupply,,trxRate) = jTrxToken.getAccountSnapshot(address(this));
        trxSupply = trxSupply*trxRate/10**18;


        return (thisBal+lpVal+trxSupply-usdtBor, lpVal, trxSupply, usdtBor);
    }

    function getAccountLiquidity() public view returns(uint256, uint256, uint256){
        uint256 err;
        uint256 excess;
        uint256 shortage;

        (err, excess, shortage) = justLendContract.getAccountLiquidity(address(this));

        return (err, excess, shortage);
    }

    function getEquityRatio() public view returns(uint256, uint256, uint256) {
        (uint256 equity,,,) = getEquityValue();
        uint256 capital = _totalDeposits + _totalPendingWithdraw;
        uint256 margin = 0;
        uint256 shortage = 0;

        if (equity > capital) {
            margin = equity-capital;
        } else {
            shortage = capital - equity;
        }

        return (equity * 1000 / capital, margin, shortage);
    }


    //
    // Set contract addresses
    //

	function setUsddAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		usddToken = IERC20(tokenAddress);
	}

	function setUsdtAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		usdtToken = IERC20(tokenAddress);
	}

    function setJUsddAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		jUsddToken = IJToken(tokenAddress);
	}

    function setJUsdtAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		jUsdtToken = IJToken(tokenAddress);
	}

   function setJTrxAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		jTrxToken = IJTRX(tokenAddress);
	}

   function setSunAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		sunToken = IERC20(tokenAddress);
	}

   function setJstAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		jstToken = IERC20(tokenAddress);
	}

   function setSsUsddTrxAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		ssUsddTrxToken = IERC20(tokenAddress);
        ssUsddTrxContract = ISunSwap(tokenAddress);
	}

	function set2PoolAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		stableSwapContract = IStableSwap2P(contractAddress);
	}

	function setSsSunTrxAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		ssSunTrxContract = ISunSwap(contractAddress);
	}

	function setSsJstTrxAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		ssJstTrxContract = ISunSwap(contractAddress);
	}

	function setJusteLendAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		justLendContract = IComptroller(contractAddress);
	}

	function setFarmAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		farmTrxUsddContract = IFarm(contractAddress);
	}

	function setFarmRewardsAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		farmRewardsContract = IRewards(contractAddress);
	}

	function setBuybackAddr(address account) public onlyAdmin {
	    require(account != address(0), "INVALID_ADDRESS");
		buybackAccount = account;
	}

	function setDexAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		ustxDex = IDex(contractAddress);
	}

	function setUstxAddr(address tokenAddress) public onlyAdmin {
	    require(tokenAddress != address(0), "INVALID_ADDRESS");
		ustxToken = IERC20(tokenAddress);
	}

	function setLimits(uint256 maxUser, uint256 maxTotal) public onlyAdmin {
        _maxPerAccount = maxUser;
        _maxTotal = maxTotal;
	}

	function setRewardsPerc(uint256 userPerc, uint256 buybackPerc) public onlyAdmin {
        require(userPerc >= 75, "USER SHARE AT LEAST 75");
        require(userPerc + buybackPerc <= 100, "CHECK PERCENTAGES");
        userRewardPerc = userPerc;
        buybackRewardPerc = buybackPerc;
	}

	function setDepositEnable(uint256 enable) public onlyAdmin {
        _depositEnable = enable;
	}

	function setSafetyMargin(uint256 margin) public onlyAdmin {
        safetyMargin = margin;
	}

    /**
	* @dev Function to withdraw lost tokens balance (only admin)
	* @param tokenAddr Token address
	*/
	function claimToken(address tokenAddr, uint256 amount) public onlyAdmin returns(uint256) {
	    require(tokenAddr != address(0), "INVALID_ADDRESS");

		IERC20 token = IERC20(tokenAddr);

        uint256 toMove = amount;
		if (amount == 0) {
            toMove = token.balanceOf(address(this));
        }

		token.transfer(msg.sender,toMove);

		return toMove;
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

    /* ========== MODIFIERS ========== */

    modifier updateReward(address account) {
        uint256 temp=0;

        if (_lastUpdate[account] == 0) {
            _lastUpdate[account] = currentEpoch;
        }

        for (uint i=_lastUpdate[account];i<currentEpoch;i++) {
            temp += _rewardRates[i];      //changed
        }

        _rewards[account]+=temp*_balances[account]/1e18;
        _lastUpdate[account] = currentEpoch;
        _;
    }

    // V1.1 fixed missing setLpRatio function

    function setLpRatio(uint256 lpPerc) public onlyAdmin {
        lpRatio = lpPerc;
	}

    /* ================ V2 functions =============== */

    function jlClaim(uint256 merkleIndex, uint256 index, uint256 amount, bytes32[] calldata merkleProof) public onlyAdmin {
        jlDistributorContract.claim(merkleIndex, index, amount, merkleProof);
    }

    function setDistributorAddr(address contractAddress) public onlyAdmin {
	    require(contractAddress != address(0), "INVALID_ADDRESS");
		jlDistributorContract = IMerkleDistributor(contractAddress);
	}
}
