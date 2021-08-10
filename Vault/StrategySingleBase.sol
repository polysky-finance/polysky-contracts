// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IStrategySirius.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";
import "./StrategyBase.sol";

abstract contract StrategySingleBase is StrategyBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    address[] public earnedToWantPath;
    address[] public wantToEarnedPath;
    address[] public wmaticToWantPath;

    constructor(
        address _wantAddress,
        address _earnedAddress,
        address _uniRouterAddress,
        address _masterChef,
        uint256 _pid,
		bool _isBurning
    ) StrategyBase(
        _wantAddress,
        _earnedAddress,
        _uniRouterAddress,
        _masterChef,
        _pid,
		_isBurning
    )  public {
    }
    
    function earnedToWant() internal virtual override{        
        if(earnedAddress != wantAddress){
            uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
            
            if (earnedAmt > 0) {
                _safeSwap(
                    earnedAmt,
                    earnedToWantPath,
                    address(this)
                );
            }
        }
    }

    function wmaticToWant() internal virtual override{
        
        if (wmaticAddress != wantAddress) {
            uint256 wmaticAmt = IERC20(wmaticAddress).balanceOf(address(this));
            _safeSwap(
                    wmaticAmt,
                    wmaticToWantPath,
                    address(this)
            );
        }
    }

    function convertDustToEarned() external virtual override nonReentrant whenNotPaused {
        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));
        if(earnedAmt > 0){
            if (earnedAddress != wantAddress) {
                // Swap half earned to token0
                _safeSwap(
                    earnedAmt,
                    earnedToWantPath,
                    address(this)
                );
            }
        }
    }    
    
    function _resetAllowances() internal virtual override {
    }
}