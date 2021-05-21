// UpStableToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;

import "./ERC20.sol";
import "./ERC20Detailed.sol";
import "./AdminRole.sol";
import "./Pausable.sol";
import "./ReentrancyGuard.sol";

contract UpStableToken is ERC20,ERC20Detailed,Pausable,ReentrancyGuard {
    uint256 private _basisPointsRate = 0;
    uint256 private constant MAX_SETTABLE_BASIS_POINTS = 100;
    address private _feeAddress;

    constructor()
        ERC20Detailed("UpStableToken", "USTX", 6)
        AdminRole(3)        //at least two administrators always in charge + the dex contract
        public {
            _feeAddress=_msgSender();
        }


    function calcFee(uint256 _value) public view returns (uint256) {
      uint256 fee = (_value.mul(_basisPointsRate)).div(10000);

      return fee;
    }

    function transfer(address _to, uint256 _value) public whenNotPaused returns (bool) {
      uint256 fee = calcFee(_value);
      if (isAdmin(_msgSender())){   //no fees if sender is admin (DEX included)
          fee = 0;
      }
      uint256 sendAmount = _value.sub(fee);

      if (fee > 0) {
        super.transfer(_feeAddress, fee);
      }
      super.transfer(_to, sendAmount);

      return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) public whenNotPaused returns (bool) {
      uint256 fee = calcFee(_value);
      if (isAdmin(_msgSender())){   //no fees if sender is admin (DEX included)
          fee = 0;
      }
      uint256 sendAmount = _value.sub(fee);

      if (fee > 0 ) {
        super.transferFrom(_from, _feeAddress, fee);
      }
      super.transferFrom(_from, _to, sendAmount);

      return true;
    }

    function setFee(uint256 newBasisPoints) public onlyAdmin {
        // Ensure transparency by hardcoding limit beyond which fees can never be added
        require(newBasisPoints <= MAX_SETTABLE_BASIS_POINTS,"Fee cannot be set higher than MAX_SETTABLE_BASIS_POINTS");

        _basisPointsRate = newBasisPoints;

        emit FeeChanged(_basisPointsRate);
    }

    function getFee() public view returns (uint256){
        // Ensure transparency by hardcoding limit beyond which fees can never be added
        return _basisPointsRate;
    }

    // Called if contract ever adds fees
    event FeeChanged(uint256 feeBasisPoints);

    function setFeeAddress(address feeAddr) public onlyAdmin {
      require(feeAddr != address(0) && feeAddr != address(this));
      _feeAddress = feeAddr;
    }

    function mint(address account, uint256 amount) public onlyAdmin returns (bool) {
        _mint(account, amount);
        return true;
    }

    function burn(uint256 amount) public {
        _burn(_msgSender(), amount);
    }

    function burnFrom(address account, uint256 amount) public {
        _burnFrom(account, amount);
    }

    function approve(address spender, uint256 value) public whenNotPaused returns (bool) {
        return super.approve(spender, value);
    }

    function increaseAllowance(address spender, uint256 addedValue) public whenNotPaused returns (bool) {
        return super.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public whenNotPaused returns (bool) {
        return super.decreaseAllowance(spender, subtractedValue);
    }
}
