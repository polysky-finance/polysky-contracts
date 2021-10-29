// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IStrategySirius.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";
import "./Operators.sol";

abstract contract StrategyFeesBase is Ownable, ReentrancyGuard, Pausable, Operators {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public wantAddress;
    address public earnedAddress;    
    address public uniRouterAddress;

    address public constant quickRouterAddress = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;

    address public constant siriusAddress = address(0x00b1289f48e8d8ad1532e83a8961f6e8b5a134661d);
    address public constant wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    
    address public constant rewardAddress = 0x87C1Fb68428756CDd04709910AFa601F7DDd5a31;
    address public constant vaultAddress = 0x3c746568A42DaB6f576B94734D0C2199b486F916;
    address public constant feeAddress = 0xC5be13105b002aC1fcA10C066893be051Bbb90d3;

    address public vaultChefAddress = 0xe84C5999Cf13C874a9157656c4AA5e29E43d73f4;

    address public constant buyBackAddress = 0x000000000000000000000000000000000000dEaD;
	address private constant zeroAddress = 0x0000000000000000000000000000000000000000;

    uint256 public controllerFee = 25; //0.25%
    uint256 public rewardRate = 0; //0%
    uint256 public buyBackRate = 75; //0.75%
    uint256 public constant feeMaxTotal = 1000;
    uint256 public constant feeMax = 10000; // 100 = 1%
	
    //Withdrawal fees in BP
    uint256 public withdrawalFee = 0; // 0% withdraw fee
    uint256 public constant maxWithdrawalFee = 100; //1%

    uint256 public slippageFactor = 950; // 5% default slippage tolerance
    uint256 public liquiditySlippageFactor = 600; // 20% default liqidity add slippage tolerance
    uint256 public constant slippageFactorUL = 995;

    address[] public earnedToWmaticPath;
    address[] public earnedToUsdcPath;
    address[] public earnedToSiriusPath;

    address[] public wmaticToSiriusPath = [address(0x000d500b1d8e8ef31e21c99d1db9a6444d3adf1270), 0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D];
    address[] public wmaticToUsdcPath =[address(0x000d500b1d8e8ef31e21c99d1db9a6444d3adf1270), address(0x002791bca1f2de4661ed88a30c99a7a9449aa84174)];

    uint256 public  minWMaticAmountToCompound = 1e17;
    uint256 public minEarnedAmountToCompound = 1e17;
    uint256 public deadline = 600;
	
	bool public isBurning = false;

    event DeadlineChanged(uint256 oldDeadline, uint256 newDeadline);
    event SetSettings(
        uint256 controllerFee,
        uint256 rewardRate,
        uint256 buyBackRate,
        uint256 withdrawalFee,
        uint256 slippageFactor,
        uint256 liquiditySlippageFactor
    );

    function changeMinCompoundAmount(uint256 _minWMaticAmountToCompound, uint256 _minEarnedAmountToCompound) external onlyOperator{
        minEarnedAmountToCompound = _minEarnedAmountToCompound;
        minWMaticAmountToCompound = _minWMaticAmountToCompound;
    }
    
    constructor(
        address _wantAddress,
        address _earnedAddress,
        address _uniRouterAddress,
		bool _isBurning
    )  public {

        wantAddress = _wantAddress;
        earnedAddress = _earnedAddress;
        uniRouterAddress = _uniRouterAddress;
		
		isBurning = _isBurning;

        transferOwnership(vaultChefAddress);
    }

    // To pay for earn function
    function distributeFees(address _earnedAddress) internal {
        uint256 earnedAmt = IERC20(_earnedAddress).balanceOf(address(this));
        
        if (controllerFee > 0 && earnedAmt >0) {
            uint256 fee = earnedAmt.mul(controllerFee).div(feeMax);

            if (_earnedAddress == wmaticAddress) {
                IWETH(wmaticAddress).withdraw(fee);
                safeTransferETH(feeAddress, fee);
            } else {
                _safeSwap(
                    fee,
                    earnedToWmaticPath,
                    feeAddress
                );
            }
        }
    }

    function distributeRewards(address _earnedAddress) internal {
        uint256 earnedAmt = IERC20(_earnedAddress).balanceOf(address(this));
        
        if (rewardRate > 0 && earnedAmt > 0) {
            uint256 fee = earnedAmt.mul(rewardRate).div(feeMax);
    
            uint256 usdcBefore = IERC20(usdcAddress).balanceOf(address(this));
            _safeSwap(
                fee,
                _earnedAddress == wmaticAddress ? wmaticToUsdcPath : earnedToUsdcPath,
                address(this)
            );
            
            uint256 usdcConverted = IERC20(usdcAddress).balanceOf(address(this)).sub(usdcBefore);
            
            approve(usdcAddress, rewardAddress, usdcConverted);
            IStrategySirius(rewardAddress).depositReward(usdcConverted);
        }
    }

    function buyBack(address _earnedAddress) internal {
        uint256 earnedAmt = IERC20(_earnedAddress).balanceOf(address(this));
        
        if (buyBackRate > 0 && earnedAmt > 0) {
            uint256 buyBackAmt = earnedAmt.mul(buyBackRate).div(feeMax);
            if(_earnedAddress == siriusAddress){
                IERC20(siriusAddress).transfer(buyBackAddress, buyBackAmt);
				return;
            }
			
			if(!isBurning){
				//Send to vault address. Used to setup the burning vault
				IERC20(_earnedAddress).transfer(vaultAddress, buyBackAmt);
				return;				
			}			
			
			//Convert earned to wmatic using uniRouter if earned is not wmatic
			if(_earnedAddress != wmaticAddress){
			    uint256 wmaticBefore = IERC20(wmaticAddress).balanceOf(address(this));
			    _safeSwap(
                    buyBackAmt,
					earnedToWmaticPath,
                    address(this)
                );
				uint256 wmaticAfter = IERC20(wmaticAddress).balanceOf(address(this));
				buyBackAmt = wmaticAfter.sub(wmaticBefore);
			}
			
			//Buy SIRIUS using quick router. Because our main liquidity is with quickswap and uniRouter 
            //may not be same as quickRouter
            _safeSwapQuick(
                buyBackAmt,
                wmaticToSiriusPath,
                buyBackAddress
            );
        }
    }

   
    function setSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawalFee,
        uint256 _slippageFactor,
        uint256 _liquiditySlippageFactor
    ) external virtual onlyOperator {
        if(!isBurning){		    
			require(_controllerFee.add(_rewardRate).add(_buyBackRate) <= feeMaxTotal, "Max fee of 10%");
		}else{
			//Burning vaults can have up to 100% buybackRate
			require(_controllerFee.add(_rewardRate).add(_buyBackRate) <= 10000, "Max fee of 100%");
		}
        require(_withdrawalFee <= maxWithdrawalFee, "_withdrawFee > maxWithdrawalFee!");
        require(_slippageFactor <= slippageFactorUL, "_slippageFactor too high");
        require(_liquiditySlippageFactor <= slippageFactorUL, "_liquiditySlippageFactor too high");
        controllerFee = _controllerFee;
        rewardRate = _rewardRate;
        buyBackRate = _buyBackRate;
        withdrawalFee = _withdrawalFee;
        slippageFactor = _slippageFactor;
        liquiditySlippageFactor = _liquiditySlippageFactor;

        emit SetSettings(
            _controllerFee,
            _rewardRate,
            _buyBackRate,
            _withdrawalFee,
            _slippageFactor,
            _liquiditySlippageFactor
        );
    }

    function setDeadline(uint256 _deadline) external onlyOperator{
        require(_deadline > 10, 'setDeadline: too small');
        emit DeadlineChanged(deadline, _deadline);
        deadline = _deadline;
    }

    function _safeSwap(
        uint256 _amountIn,
        address[] memory _path,
        address _to
    ) internal {

        approve(_path[0], uniRouterAddress, _amountIn);

        uint256[] memory amounts = IUniRouter02(uniRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];

        IUniRouter02(uniRouterAddress).swapExactTokensForTokens(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            now.add(deadline)
        );
    }

    function _safeSwapQuick(
        uint256 _amountIn,
        address[] memory _path,
        address _to
    ) internal {
        
        approve(_path[0], quickRouterAddress, _amountIn);
        
        uint256[] memory amounts = IUniRouter02(quickRouterAddress).getAmountsOut(_amountIn, _path);
        uint256 amountOut = amounts[amounts.length.sub(1)];
        
        IUniRouter02(quickRouterAddress).swapExactTokensForTokens(
            _amountIn,
            amountOut.mul(slippageFactor).div(1000),
            _path,
            _to,
            now.add(deadline)
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }
	
	function approve(address tokenAddress, address spenderAddress, uint256 amount) internal {
	    IERC20(tokenAddress).safeApprove(spenderAddress, uint256(0));
        IERC20(tokenAddress).safeIncreaseAllowance(
            spenderAddress,
            amount
        );
	}

    receive() external payable {}
}