// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// openzeppelin v3.1.0
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IStrategySirius.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";
import "./StrategyFeesBase.sol";
import "./libs/IWETH.sol";

abstract contract StrategyBase is StrategyFeesBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    //For masterchef requiring referrer
    address internal constant referralAddress = 0x97Ddc7d5737A11AF922898312Cc15bf7dA3b4dF9;

    uint256 public lastEarnBlock = block.number;
    uint256 public sharesTotal = 0;

    //Virtual functions specific to each masterchef
    function stake(uint256 _wantAmount)  internal virtual;
    function harvest() internal virtual;
    function unstake(uint256 _amount) internal virtual;
    function earnedToWant() internal virtual;
    function wmaticToWant() internal virtual;
    function emergencyWithdraw() internal virtual;
    function vaultSharesTotal() virtual public view returns (uint256);

    //Masterchef address
    address public masterChef;
    uint256 public pid;
    
    //Minimum interval between for the optimised earn call. uint256(-1) means no earn is called
    uint256 public compoundCycle = 100; 
    
    constructor(
        address _wantAddress,
        address _earnedAddress,
        address _uniRouterAddress,
        address _masterChef,
        uint256 _pid,
		bool _isBurning
    ) StrategyFeesBase(
        _wantAddress,
        _earnedAddress,
        _uniRouterAddress,
		_isBurning
    )  public {        
        masterChef = _masterChef;
        pid = _pid;
    }

    event CompoundCycleChanged(uint256 indexed oldCycle, uint256 indexed newCycle);
    
    function changeCompoundCycle(uint256 _compoundCycle) external onlyGov nonReentrant whenNotPaused {
        emit CompoundCycleChanged(compoundCycle, _compoundCycle);
        compoundCycle = _compoundCycle;
    }
    
    function deposit(uint256 _wantAmt) external onlyOwner nonReentrant whenNotPaused returns (uint256) {
        // Call must happen before transfer
        uint256 wantLockedBefore = wantLockedTotal();
        
        uint256 balanceBefore = IERC20(wantAddress).balanceOf(address(this));
        IERC20(wantAddress).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );
        uint256 balanceAfter = IERC20(wantAddress).balanceOf(address(this));

        uint256 balanceChange = balanceAfter.sub(balanceBefore);
        if(_wantAmt > balanceChange){
            _wantAmt = balanceChange;
        }

        // Proper deposit amount for tokens with fees, or vaults with deposit fees
        uint256 sharesAdded = _farm(_wantAmt);
        if (sharesTotal > 0) {
            sharesAdded = sharesAdded.mul(sharesTotal).div(wantLockedBefore);
        }
        sharesTotal = sharesTotal.add(sharesAdded);

        return sharesAdded;
    }

    function _farm(uint256 _wantAmt) internal returns (uint256) {
        if (_wantAmt == 0) return 0;
        
        uint256 sharesBefore = vaultSharesTotal();
        approve(wantAddress, masterChef, _wantAmt);        
        stake(_wantAmt);
        uint256 sharesAfter = vaultSharesTotal();
        
        return sharesAfter.sub(sharesBefore);
    }

    function withdraw(uint256 _wantAmt) external onlyOwner nonReentrant returns (uint256) {
        require(_wantAmt > 0, "_wantAmt is 0");
        
        uint256 balance = IERC20(wantAddress).balanceOf(address(this));
        
        // Check if strategy has tokens from panic
        if (_wantAmt > balance) {
            unstake(_wantAmt.sub(balance));
            balance = IERC20(wantAddress).balanceOf(address(this));
        }

        if (_wantAmt > balance) {
            _wantAmt = balance;
        }

        if (_wantAmt > wantLockedTotal()) {
            _wantAmt = wantLockedTotal();
        }

        uint256 sharesRemoved = _wantAmt.mul(sharesTotal).div(wantLockedTotal());
        if (sharesRemoved > sharesTotal) {
            sharesRemoved = sharesTotal;
        }
        sharesTotal = sharesTotal.sub(sharesRemoved);
        
        // Withdraw fee
        uint256 withdrawFee = _wantAmt
            .mul(withdrawalFee)
            .div(10000);

        IERC20(wantAddress).safeTransfer(vaultAddress, withdrawFee);  
        _wantAmt = _wantAmt.sub(withdrawFee);
        IERC20(wantAddress).safeTransfer(vaultChefAddress, _wantAmt);

        return sharesRemoved;
    }

    //To be called from vault chef for bulk earn to save gas fees and optimise returns
    function optimisedEarn() external nonReentrant whenNotPaused onlyOwner {
        //optimisedEarn disabled
        if(compoundCycle == uint256(-1)){
            return;
        }
        if(block.number > lastEarnBlock.add(compoundCycle)){
            _earn();
        }
    }

    //Calling directly by gov, for individual calls of the compound function
    function earn() external nonReentrant whenNotPaused onlyGov{
        _earn();
    }

    function _earn() internal {
        harvest();

        //Convert wmatic token to want
        uint256 wmaticAmt = IERC20(wmaticAddress).balanceOf(address(this));
		uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
		
		//The second check to avoid ditributing fees, rewards and buyback multiple times
        if (wmaticAmt > minWMaticAmountToCompound && earnedAmt > minEarnedAmountToCompound) {
            //distribute fees and buy back
            distributeFees(wmaticAddress);
            distributeRewards(wmaticAddress);
            buyBack(wmaticAddress);

            //convert wmatic token to want token
            wmaticToWant();
        }

        //Convert earned token to want        
        if (earnedAmt > minEarnedAmountToCompound) {
            //distribute fees and buy back
            distributeFees(earnedAddress);
            distributeRewards(earnedAddress);
            buyBack(earnedAddress);

            //convert earned token to want token
            earnedToWant();
        }
    
        lastEarnBlock = block.number;
        
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        _farm(wantAmt);
    }

    // Emergency!!
    function pause() external onlyGov {
        _pause();
    }

    // False alarm
    function unpause() external onlyGov {
        _unpause();
    }   

    function wantLockedTotal() public view returns (uint256) {
        return IERC20(wantAddress).balanceOf(address(this))
        .add(vaultSharesTotal());
    }

    function panic() external onlyGov {
        _pause();
        unstake(vaultSharesTotal());
    }

    function emergencyPanic() external  virtual onlyGov {
        _pause();
        emergencyWithdraw();
    }

    function unpanic() external onlyGov {
        _unpause();
        uint256 wantAmt = IERC20(wantAddress).balanceOf(address(this));
        _farm(wantAmt);
    }
}