// UstxDex.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;

import "./ERC20.sol";
import "./ERC20Detailed.sol";
import "./UpStableToken.sol";
import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./Pausable.sol";
import "./AdminRole.sol";



contract UstxDEX is ERC20,ReentrancyGuard,Pausable {

  /***********************************|
  |        Variables && Events        |
  |__________________________________*/

  //Constants
  uint256 private constant MAX_FEE = 250;   //maximum fee in BP (2.5%)
  uint256 private constant MAX_LAUNCH_FEE = 1000;  //maximum team fee during launchpad (10%)


  // Variables
  string public name;         // UstxDEX V1
  string public symbol;       // USTXDEX-V1
  uint256 public decimals;     // 6
  UpStableToken Token;       // address of the TRC20 token traded on this contract
  IERC20 Tusdt;              // address of the reserve token USDT
  using SafeERC20 for IERC20;
  using SafeERC20 for UpStableToken;

  uint256 private _feeBuy;           //buy fee in basis points
  uint256 private _feeSell;          //sell fee in basis points
  uint256 private _targetRatio;     //target reserve ratio in TH (1000s) to circulating cap
  uint256 private _expFactor;       //expansion factor in TH
  uint256 private _dampFactor;      //damping factor in TH
  uint256 private _minExp;          //minimum expansion in TH
  uint256 private _maxDamp;         //maximum damping in TH
  uint256 private _collectedFees;   //amount of collected fees
  uint256 private _launchEnabled;   //launchpad mode if >1
  uint256 private _launchTargetSize;   //number of tokens reserved for launchpad
  uint256 private _launchPrice;     //Launchpad price
  uint256 private _launchBought;  //number of tokens bought so far in Launchpad
  uint256 private _launchMaxLot;    //max number of usdtSold for a single operation during Launchpad
  uint256 private _launchFee;       //Launchpad fee
  address private _launchTeamAddr;  //Launchpad team address

  // Events
  event TokenBuy(address indexed buyer, uint256 indexed usdtSold, uint256 indexed tokensBought, uint256 fees);
  event TokenSell(address indexed buyer, uint256 indexed tokensSold, uint256 indexed usdtBought, uint256 fees);
  event Snapshot(address indexed operator, uint256 indexed usdtBalance, uint256 indexed tokenBalance);


  /***********************************|
  |            Constructor            |
  |__________________________________*/

  /**
   * @dev Constructor
   *
   */
  constructor (address tradeTokenAddr, address reserveTokenAddr)
    AdminRole(2)        //at least two administrsators always in charge
    public {
        require(
          tradeTokenAddr != address(0) && reserveTokenAddr != address(0),
          "INVALID_ADDRESS"
        );
        Token = UpStableToken(tradeTokenAddr);
        Tusdt = IERC20(reserveTokenAddr);
        _launchTeamAddr = _msgSender();
        name = "UstxDEX V1";
        symbol = "USTXDEX-V1";
        decimals = 6;
        _feeBuy = 0; //0%
        _feeSell = 100; //1%
        _targetRatio = 200;
        _expFactor = 1000;
        _dampFactor = 1000;
        _minExp = 100;
        _maxDamp = 250;
        _collectedFees = 0;
        _launchEnabled = 0;
      }


  /***********************************|
  |        Exchange Functions         |
  |__________________________________*/


  /**
   * @notice Fallback function.
   * @dev revert
   */
  function () external payable {
    revert("Cannot receive TRX");
  }

  /**
   * @dev function to get current block time
   *
   */
  function getBlockTime() public view returns (uint256) {
    return block.timestamp;
  }

  /**
   * @dev internal function to get expansion correction
   *
   */
    function _getExp(uint256 tokenReserve, uint256 usdtReserve) private view returns (uint256,uint256) {
        uint256 tokenCirc = Token.totalSupply();        //total
        tokenCirc = tokenCirc.sub(tokenReserve);
        uint256 price = getPrice();         //multiplied by 10**decimals
        uint256 cirCap = price.mul(tokenCirc);      //multiplied by 10**decimals
        uint256 ratio = usdtReserve.mul(1000000000).div(cirCap);
        uint256 exp = ratio.mul(1000).div(_targetRatio);
        if (exp<1000) {
            exp=1000;
        }
        exp = exp.sub(1000);
        exp=exp.mul(_expFactor).div(1000);
        if (exp<_minExp) {
            exp=_minExp;
        }
        if (exp>1000) {
            exp = 1000;
        }
        return (exp,ratio);
    }

  /**
   * @dev Internal function to get k exponential factor for expansion
   *
   */
    function _getKXe(uint256 pool, uint256 trade, uint256 exp) private pure returns (uint256) {
        uint256 temp = 1000-exp;
        temp = trade.mul(temp);
        temp = temp.div(1000);
        temp = temp.add(pool);
        temp = temp.mul(1000000000);
        uint256 kexp = temp.div(pool);
        return kexp;
    }

  /**
   * @dev Internal function to get k exponential factor for damping
   *
   */
    function _getKXd(uint256 pool, uint256 trade, uint256 exp) private pure returns (uint256) {
        uint256 temp = 1000-exp;
        temp = trade.mul(temp);
        temp = temp.div(1000);
        temp = temp.add(pool);
        uint256 kexp = pool.mul(1000000000).div(temp);
        return kexp;
    }

  /**
   * @dev internal function to get amount of tokens bought and minted
   *
   */
    function _getBoughtMinted(uint256 usdtSold, uint256 tokenReserve, uint256 usdtReserve) private view returns (uint256,uint256,uint256) {
        uint256 fees = usdtSold.mul(_feeBuy).div(10000);
        uint256 usdtSoldNet = usdtSold.sub(fees);

        (uint256 exp,) = _getExp(tokenReserve,usdtReserve);

        uint256 kexp = _getKXe(usdtReserve,usdtSoldNet,exp);

        uint256 temp = tokenReserve.mul(usdtReserve);       //k
        temp = temp.mul(kexp);
        temp = temp.mul(kexp);
        uint256 kn = temp.div(1000000000000000000);                 //uint256 kn=tokenReserve.mul(usdtReserve).mul(kexp).mul(kexp).div(1000000);

        temp = tokenReserve.mul(usdtReserve);               //k
        usdtReserve = usdtReserve.add(usdtSoldNet);          //uint256 usdtReserveNew= usdtReserve.add(usdtSoldNet);
        temp = temp.div(usdtReserve);                       //USTXamm
        uint256 tokensBought = tokenReserve.sub(temp);      //out=tokenReserve-USTXamm

        temp=kn.div(usdtReserve);                           //USXTPool_n
        uint256 minted=temp.add(tokensBought).sub(tokenReserve);

        return (tokensBought, minted, fees);
    }

  /**
   * @dev Internal function to get damping correction
   *
   */
    function _getDamp(uint256 tokenReserve, uint256 usdtReserve) private view returns (uint256,uint256) {
        uint256 tokenCirc = Token.totalSupply();        //total
        tokenCirc = tokenCirc.sub(tokenReserve);
        uint256 price = getPrice();         //multiplied by 10**decimals
        uint256 cirCap = price.mul(tokenCirc);      //multiplied by 10**decimals
        uint256 ratio = usdtReserve.mul(1000000000).div(cirCap);  //in TH
        if (ratio>_targetRatio) {
            ratio=_targetRatio;
        }
        uint256 damp = _targetRatio.sub(ratio);
        damp = damp.mul(_dampFactor).div(_targetRatio);

        if (damp<_maxDamp) {
            damp=_maxDamp;
        }
        if (damp>1000) {
            damp = 1000;
        }
        return (damp,ratio);
    }

  /**
   * @dev Internal function to get number of USDT bought and tokens burned
   *
   */
    function _getBoughtBurned(uint256 tokenSold, uint256 tokenReserve, uint256 usdtReserve) private view returns (uint256,uint256,uint256) {
        (uint256 damp,) = _getDamp(tokenReserve,usdtReserve);

        uint256 kexp = _getKXd(tokenReserve,tokenSold,damp);

        uint256 k = tokenReserve.mul(usdtReserve);           //k
        uint256 temp = k.mul(kexp);
        temp = temp.mul(kexp);
        uint256 kn = temp.div(1000000000000000000);             //uint256 kn=tokenReserve.mul(usdtReserve).mul(kexp).mul(kexp).div(1000000);

        tokenReserve = tokenReserve.add(tokenSold);             //USTXpool_n
        temp = k.div(tokenReserve);                             //USDamm
        uint256 usdtsBought = usdtReserve.sub(temp);            //out
        usdtReserve = temp;

        temp = kn.div(usdtReserve);                             //USTXPool_n

        uint256 burned=tokenReserve.sub(temp);

        temp = usdtsBought.mul(_feeSell).div(10000);       //fee
        usdtsBought = usdtsBought.sub(temp);

        return (usdtsBought, burned, temp);
    }

  /**
   * @dev Public function to preview token purchase with exact input in USDT
   *
   */
    function buyStableInputPreview(uint256 usdtSold) public view returns (uint256) {
        require(usdtSold > 0);
        uint256 tokenReserve = Token.balanceOf(address(this));
        uint256 usdtReserve = Tusdt.balanceOf(address(this));

        (uint256 tokensBought,,) = _getBoughtMinted(usdtSold,tokenReserve,usdtReserve);

        return tokensBought;
    }

  /**
   * @dev Internal function to buy tokens with exact input in USDT
   *
   */
    function _buyStableInput(uint256 usdtSold, uint256 minTokens, uint256 deadline, address buyer, address recipient) private nonReentrant returns (uint256) {
        require(deadline >= block.timestamp && usdtSold > 0 && minTokens > 0);
        uint256 tokenReserve = Token.balanceOf(address(this));
        uint256 usdtReserve = Tusdt.balanceOf(address(this));

        (uint256 tokensBought, uint256 minted, uint256 fees) = _getBoughtMinted(usdtSold,tokenReserve,usdtReserve);
        _collectedFees = _collectedFees.add(fees);

        require(tokensBought >= minTokens);
        if (minted>0) {
            Token.mint(address(this),minted);
        }
        Tusdt.safeTransferFrom(buyer, address(this), usdtSold);
        Token.safeTransfer(address(recipient),tokensBought);
        emit TokenBuy(buyer, usdtSold, tokensBought, fees);
        emit Snapshot(buyer, Tusdt.balanceOf(address(this)), Token.balanceOf(address(this)));

        return tokensBought;
    }

  /**
   * @dev Internal function to buy tokens during launchpad with exact input in USDT
   *
   */
    function _buyLaunchpadInput(uint256 usdtSold, uint256 minTokens, uint256 deadline, address buyer, address recipient) private nonReentrant returns (uint256) {
        require(deadline >= block.timestamp && usdtSold > 0 && minTokens > 0);

        uint256 tokensBought = usdtSold.mul(10**decimals).div(_launchPrice);
        uint256 fee = usdtSold.mul(_launchFee).div(10000);

        require(tokensBought >= minTokens);
        _launchBought = _launchBought.add(tokensBought);
        Token.mint(address(this),tokensBought);                     //mint new tokens

        Tusdt.safeTransferFrom(buyer, address(this), usdtSold);     //add usdtSold to reserve
        Tusdt.safeTransferUSDT(_launchTeamAddr,fee);                //transfer fees to team
        Token.safeTransfer(address(recipient),tokensBought);        //transfer tokens to recipient
        emit TokenBuy(buyer, usdtSold, tokensBought, 0);
        emit Snapshot(buyer, Tusdt.balanceOf(address(this)), Token.balanceOf(address(this)));

        return tokensBought;
    }

  /**
   * @dev Public function to preview token sale with exact input in tokens
   *
   */
  function sellStableInputPreview(uint256 tokensSold) public view returns (uint256) {
        require(tokensSold > 0);
        uint256 tokenReserve = Token.balanceOf(address(this));
        uint256 usdtReserve = Tusdt.balanceOf(address(this));

        (uint256 usdtsBought,,) = _getBoughtBurned(tokensSold,tokenReserve,usdtReserve);

        return usdtsBought;
  }

  /**
   * @dev Internal function to sell tokens with exact input in tokens
   *
   */
  function _sellStableInput(uint256 tokensSold, uint256 minUsdts, uint256 deadline, address buyer, address recipient) private nonReentrant returns (uint256) {
        require(deadline >= block.timestamp && tokensSold > 0 && minUsdts > 0);
        uint256 tokenReserve = Token.balanceOf(address(this));
        uint256 usdtReserve = Tusdt.balanceOf(address(this));

        (uint256 usdtsBought, uint256 burned, uint256 fees) = _getBoughtBurned(tokensSold,tokenReserve,usdtReserve);
        _collectedFees = _collectedFees.add(fees);

        require(usdtsBought >= minUsdts);
         if (burned>0) {
            Token.burn(burned);
        }
        Token.safeTransferFrom(buyer, address(this), tokensSold);
        Tusdt.safeTransferUSDT(recipient,usdtsBought);
        emit TokenSell(buyer, tokensSold, usdtsBought, fees);
        emit Snapshot(buyer,Tusdt.balanceOf(address(this)),Token.balanceOf(address(this)));

        return usdtsBought;
  }

  /**
   * @dev public function to buy tokens during launchpad
   *
   */
  function  buyTokenLaunchInput(uint256 rSell, uint256 minTokens, uint256 deadline)  public whenNotPaused returns (uint256)  {
    require(_launchEnabled>0,"Function allowed only during launchpad");
    require(_launchBought<_launchTargetSize,"Launchpad target reached!");
    require(rSell<=_launchMaxLot,"Order too big for Launchpad");
    return _buyLaunchpadInput(rSell, minTokens, deadline, msg.sender, msg.sender);
  }

  /**
   * @dev public function to buy tokens during launchpad and transfer them to recipient
   *
   */
  function buyTokenLaunchTransferInput(uint256 rSell, uint256 minTokens, uint256 deadline, address recipient) public whenNotPaused returns(uint256) {
    require(_launchEnabled>0,"Function allowed only during launchpad");
    require(recipient != address(this) && recipient != address(0),"Recipient cannot be DEX or address 0");
    require(_launchBought<_launchTargetSize,"Launchpad target reached!");
    require(rSell<=_launchMaxLot,"Order too big for Launchpad");
    return _buyLaunchpadInput(rSell, minTokens, deadline, msg.sender, recipient);
  }

  /**
   * @dev public function to buy tokens
   *
   */
  function  buyTokenInput(uint256 rSell, uint256 minTokens, uint256 deadline)  public whenNotPaused returns (uint256)  {
    require(_launchEnabled==0,"Function not allowed during launchpad");
    return _buyStableInput(rSell, minTokens, deadline, msg.sender, msg.sender);
  }

  /**
   * @dev public function to buy tokens and transfer them to recipient
   *
   */
  function buyTokenTransferInput(uint256 rSell, uint256 minTokens, uint256 deadline, address recipient) public whenNotPaused returns(uint256) {
    require(_launchEnabled==0,"Function not allowed during launchpad");
    require(recipient != address(this) && recipient != address(0),"Recipient cannot be DEX or address 0");
    return _buyStableInput(rSell, minTokens, deadline, msg.sender, recipient);
  }

   /**
   * @dev public function to sell tokens
   *
   */
  function sellTokenInput(uint256 tokensSold, uint256 minUsdts, uint256 deadline) public whenNotPaused returns (uint256) {
    require(_launchEnabled==0,"Function not allowed during launchpad");
    return _sellStableInput(tokensSold, minUsdts, deadline, msg.sender, msg.sender);
  }

  /**
   * @dev public function to sell tokens and trasnfer USDT to recipient
   *
   */
  function sellTokenTransferInput(uint256 tokensSold, uint256 minUsdts, uint256 deadline, address recipient) public whenNotPaused returns (uint256) {
    require(_launchEnabled==0,"Function not allowed during launchpad");
    require(recipient != address(this) && recipient != address(0),"Recipient cannot be DEX or address 0");
    return _sellStableInput(tokensSold, minUsdts, deadline, msg.sender, recipient);
  }

    /**
    * @dev public function to setup the reserve after launchpad
    *
    */
    function setupReserve(uint256 startPrice) public onlyAdmin whenPaused returns (uint256) {
        require(startPrice>0,"Price cannot be 0");
        uint256 tokenReserve = Token.balanceOf(address(this));
        uint256 usdtReserve = Tusdt.balanceOf(address(this));

        uint256 newReserve = usdtReserve.mul(10**decimals).div(startPrice);
        uint256 temp;
        if (newReserve>tokenReserve) {
            temp = newReserve.sub(tokenReserve);
            Token.mint(address(this),temp);
        } else {
            temp = tokenReserve.sub(newReserve);
            Token.burn(temp);
        }
        return newReserve;
    }

  /**************************************|
  |     Getter and Setter Functions      |
  |_____________________________________*/

  /**
   * @dev function to set Token address (only admin)
   *
   */
    function setTokenAddr(address tokenAddress) public onlyAdmin {
        require(tokenAddress != address(0), "INVALID_ADDRESS");
        Token = UpStableToken(tokenAddress);
    }

  /**
   * @dev function to set USDT address (only admin)
   *
   */
    function setReserveTokenAddr(address reserveAddress) public onlyAdmin {
        require(reserveAddress != address(0), "INVALID_ADDRESS");
        Tusdt = IERC20(reserveAddress);
    }

  /**
   * @dev function to set fees (only admin)
   * fees in basis points
   *
   */
    function setFees(uint256 feeBuy, uint256 feeSell) public onlyAdmin {
        require(feeBuy<=MAX_FEE && feeSell<=MAX_FEE,"Fees cannot be higher than MAX_FEE");
        _feeBuy=feeBuy;
        _feeSell=feeSell;
    }

  /**
   * @dev function to get fees
   * fees in basis points
   *
   */
    function getFees() public view returns (uint256, uint256) {
        return (_feeBuy, _feeSell);
    }

  /**
   * @dev function to set target ratio level (only admin)
   * ratio in thousandths
   *
   */
    function setTargetRatio(uint256 ratio) public onlyAdmin {
        require(ratio<10000 && ratio>100,"Target ratio must be between 1% and 100%");
        _targetRatio = ratio;       //in TH
    }

  /**
   * @dev function to get target ratio level
   * ratio in thousandths
   *
   */
    function getTargetRatio() public view returns (uint256) {
        return _targetRatio;
    }

  /**
   * @dev function to get target ratio level
   * ratio in thousandths
   *
   */
    function getCurrentRatio() public view returns (uint256) {
        uint256 tokenReserve = Token.balanceOf(address(this));
        uint256 usdtReserve = Tusdt.balanceOf(address(this));
        uint256 tokenCirc = Token.totalSupply();        //total
        tokenCirc = tokenCirc.sub(tokenReserve);
        uint256 price = getPrice();         //multiplied by 10**decimals
        uint256 cirCap = price.mul(tokenCirc);      //multiplied by 10**decimals
        uint256 ratio = usdtReserve.mul(1000000000).div(cirCap);  //in TH
        return ratio;
    }

  /**
   * @dev function to set target expansion factors (only admin)
   * values in thousandths
   *
   */
    function setExpFactors(uint256 expF, uint256 minExp) public onlyAdmin {
        require(expF<=10000 && minExp<=1000,"Expansion factor cannot be more than 1000% and the minimum expansion cannot be over 100%");
        _expFactor=expF;
        _minExp=minExp;
    }

  /**
   * @dev function to get expansion factors
   * values in thousandths
   *
   */
    function getExpFactors() public view returns (uint256, uint256) {
        return (_expFactor,_minExp);
    }

  /**
   * @dev function to set target damping factors (only admin)
   * values in thousandths
   *
   */
    function setDampFactors(uint256 dampF, uint256 maxDamp) public onlyAdmin {
        require(dampF<=1000 && maxDamp<=1000,"Damping factor cannot be more than 100% and the maximum damping be over 100%");
        _dampFactor=dampF;
        _maxDamp=maxDamp;
    }

  /**
   * @dev function to get damping factors
   * values in thousandths
   *
   */
    function getDampFactors() public view returns (uint256, uint256) {
        return (_dampFactor,_maxDamp);
    }

  /**
   * @dev function to get current price
   *
   */
    function getPrice() public view returns (uint256) {
        if (_launchEnabled>0) {
            return (_launchPrice);
        }else {
            uint256 tokenReserve = Token.balanceOf(address(this));
            uint256 usdtReserve = Tusdt.balanceOf(address(this));
            return (usdtReserve.mul(10**decimals).div(tokenReserve));      //price with decimals
        }
    }

  /**
   * @notice Public price function for USDT to Token trades with an exact input.
   * @param tUSDTs_sold Amount of USDT sold.
   * @return Amount of Tokens that can be bought with input USDT.
   */
  function getBuyTokenInputPrice(uint256 tUSDTs_sold) public view returns (uint256) {
    require(tUSDTs_sold > 0, "USDT sold must greater than 0");
    uint256 tokenReserve = Token.balanceOf(address(this));
    uint256 usdtReserve = Tusdt.balanceOf(address(this));

    (uint256 tokensBought,,) = _getBoughtMinted(tUSDTs_sold,tokenReserve,usdtReserve);
    return tokensBought;
  }

  /**
   * @notice Public price function for Token to USDT trades with an exact input.
   * @param tokensSold Amount of Tokens sold.
   * @return Amount of USDT that can be bought with input Tokens.
   */
  function getSellTokenInputPrice(uint256 tokensSold) public view returns (uint256) {
    require(tokensSold > 0, "tokens sold must greater than 0");
    uint256 tokenReserve = Token.balanceOf(address(this));
    uint256 usdtReserve = Tusdt.balanceOf(address(this));

    (uint256 usdtsBought,,) = _getBoughtBurned(tokensSold,tokenReserve,usdtReserve);
    return usdtsBought;
  }

  /**
   * @return Address of Token that is sold on this exchange.
   */
  function getTokenAddress() public view returns (address) {
    return address(Token);
  }

  /**
   * @return Address of USDT
   */
  function getReserveAddress() public view returns (address) {
    return address(Tusdt);
  }

 /**
   * @dev function to get current reserves balance
   *
   */
    function getBalances() public view returns (uint256,uint256,uint256,uint256) {
        uint256 tokenReserve = Token.balanceOf(address(this));
        uint256 usdtReserve = Tusdt.balanceOf(address(this));
        uint256 tokenCirc = Token.totalSupply().sub(tokenReserve);
        return (usdtReserve,tokenReserve,tokenCirc,_collectedFees);
    }

  /**
   * @dev function to enable launchpad (only admin)
   *
   *
   */
    function enableLaunchpad(uint256 price, uint256 target, uint256 maxLot, uint256 fee) public onlyAdmin {
        require(_launchTeamAddr != address(0),"Before activating launchpad set team address");
        require(price>0 && target>0 && maxLot>0 && fee<=MAX_LAUNCH_FEE,"Price, target and max lotsize cannot be 0. Fee must be lower than MAX_LAUNCH_FEE");
        _launchPrice = price;       //in USDT units
        _launchTargetSize = target; //in USTX units
        _launchBought = 0;          //in USTX units
        _launchFee = fee;
        _launchMaxLot = maxLot;     //in USDT units
        _launchEnabled = 1;
    }

    /**
   * @dev function to disable launchpad (only admin)
   *
   *
   */
    function disableLaunchpad() public onlyAdmin {
        _launchEnabled = 0;
    }

    /**
   * @dev function to get launchpad status (only admin)
   *
   *
   */
    function getLaunchpadStatus() public view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        return (_launchEnabled,_launchPrice,_launchBought,_launchTargetSize,_launchMaxLot,_launchFee);
    }
  /**
   * @dev Set Launchpad team address
   */
  function setTeamAddress(address team) public onlyAdmin {
      require(team != address(0) && team != address(this));
      _launchTeamAddr = team;
  }
}
