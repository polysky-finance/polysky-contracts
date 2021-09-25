// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// openzeppelin v3.1.0
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";
import "./StrategyBase.sol";

abstract contract StrategyLPBase is StrategyBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public token0Address;
    address public token1Address;

    bool internal isWmaticPair = false;
    //Non wmatic token of token1 and token0
    address internal token;
    
    address[] public earnedToToken0Path;
    address[] public earnedToToken1Path;
    address[] public token0ToEarnedPath;
    address[] public token1ToEarnedPath;
    address[] public wmaticToToken0Path;
    address[] public wmaticToToken1Path;

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
        token0Address = IUniPair(wantAddress).token0();
        token1Address = IUniPair(wantAddress).token1();
    }

    function wmaticToWant() internal virtual override{
        uint256 wmaticAmt = IERC20(wmaticAddress).balanceOf(address(this));
        if (wmaticAddress != token0Address) {
            // Swap half of wmatic to token0
            _safeSwap(
                    wmaticAmt.div(2),
                    wmaticToToken0Path,
                    address(this)
            );
        }
    
        if (wmaticAddress != token1Address) {
            // Swap half earned to token1
            _safeSwap(
                wmaticAmt.div(2),
                wmaticToToken1Path,
                address(this)
            );
        }
        //No need to add liquidity here. This will be picked up by calls in earnedToWant
    }
    
    function earnedToWant() internal virtual override{
        uint256 earnedAmt = IERC20(earnedAddress).balanceOf(address(this));

        if(earnedAmt > 0){
            if (earnedAddress != token0Address) {
                // Swap half earned to token0
                _safeSwap(
                    earnedAmt.div(2),
                    earnedToToken0Path,
                    address(this)
                );
            }
    
            if (earnedAddress != token1Address) {
                // Swap half earned to token1
                _safeSwap(
                    earnedAmt.div(2),
                    earnedToToken1Path,
                    address(this)
                );
            }
    
            // Get want tokens, ie. add liquidity
            uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
            uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
            approve(token0Address, uniRouterAddress, token0Amt);
            approve(token1Address, uniRouterAddress, token1Amt);

            if (token0Amt > 0 && token1Amt > 0) {            
                 IUniRouter02(uniRouterAddress).addLiquidity(
                    token0Address,
                    token1Address,
                    token0Amt,
                    token1Amt,
                    token0Amt.mul(liquiditySlippageFactor).div(1000),
                    token1Amt.mul(liquiditySlippageFactor).div(1000), 
                    address(this),
                    now.add(deadline)
                );
            }
        }
    }

    function convertDustToEarned() external nonReentrant whenNotPaused {
        // Converts dust tokens into earned tokens, which will be reinvested on the next earn().

        // Converts token0 dust (if any) to earned tokens
        uint256 token0Amt = IERC20(token0Address).balanceOf(address(this));
        if (token0Amt > 0 && token0Address != earnedAddress) {
            // Swap all dust tokens to earned tokens
            _safeSwap(
                token0Amt,
                token0ToEarnedPath,
                address(this)
            );
        }

        // Converts token1 dust (if any) to earned tokens
        uint256 token1Amt = IERC20(token1Address).balanceOf(address(this));
        if (token1Amt > 0 && token1Address != earnedAddress) {
            // Swap all dust tokens to earned tokens
           _safeSwap(
                token1Amt,
                token1ToEarnedPath,
                address(this)
            );
        }
    }    
}