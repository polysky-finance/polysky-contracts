// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IStrategySirius.sol";
import "./libs/IUniPair.sol";
import "./libs/IUniRouter02.sol";

abstract contract StrategyFeesBase is Ownable, ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public wantAddress;
    address public earnedAddress;    
    address public uniRouterAddress;

    address public constant siriusAddress = address(0x00b1289f48e8d8ad1532e83a8961f6e8b5a134661d);
    address public constant wmaticAddress = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address public constant usdcAddress = 0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174;
    
    address public constant rewardAddress = 0xd3D8eC51004711A66BC005D65290A63f8867F183;
    address public constant vaultAddress = 0x3c746568A42DaB6f576B94734D0C2199b486F916;
    address public constant feeAddress = 0xC5be13105b002aC1fcA10C066893be051Bbb90d3;

    address public vaultChefAddress = 0xDf1b5a548D2B3870E01Ff561A5d2aa154eA97c8B;
    address public govAddress;

    address public constant buyBackAddress = 0x000000000000000000000000000000000000dEaD;

    uint256 public controllerFee = 75;//0.75%
    uint256 public rewardRate = 25; //0.25%
    uint256 public buyBackRate = 0;
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

    function resetAllowances() public virtual;

    event DeadlineChanged(uint256 oldDeadline, uint256 newDeadline);
    event GovChanged(address oldGovAddress, address newGovAddress); 
    event SetSettings(
        uint256 controllerFee,
        uint256 rewardRate,
        uint256 buyBackRate,
        uint256 withdrawalFee,
        uint256 slippageFactor,
        uint256 liquiditySlippageFactor
    );

    function changeMinCompoundAmount(uint256 _minWMaticAmountToCompound, uint256 _minEarnedAmountToCompound) external onlyGov{
        minEarnedAmountToCompound = _minEarnedAmountToCompound;
        minWMaticAmountToCompound = _minWMaticAmountToCompound;
    }
    
    constructor(
        address _wantAddress,
        address _earnedAddress,
        address _uniRouterAddress
    )  public {
        govAddress = msg.sender;

        wantAddress = _wantAddress;
        earnedAddress = _earnedAddress;
        uniRouterAddress = _uniRouterAddress;

        transferOwnership(vaultChefAddress);
    }

    modifier onlyGov() {
        require(msg.sender == govAddress, "!gov");
        _;
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
            
            IStrategySirius(rewardAddress).depositReward(usdcConverted);
        }
    }

    function buyBack(address _earnedAddress) internal {
        uint256 earnedAmt = IERC20(_earnedAddress).balanceOf(address(this));
        
        if (buyBackRate > 0 && earnedAmt > 0) {
            uint256 buyBackAmt = earnedAmt.mul(buyBackRate).div(feeMax);
            if(_earnedAddress == siriusAddress){
                IERC20(siriusAddress).transfer(buyBackAddress, buyBackAmt);
            }else{
                _safeSwap(
                    buyBackAmt,
                    _earnedAddress == wmaticAddress ? wmaticToSiriusPath : earnedToSiriusPath,
                    buyBackAddress
                );
            }
        }
    }

    function _resetAllowances() internal virtual {
        IERC20(earnedAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(earnedAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );

        IERC20(usdcAddress).safeApprove(rewardAddress, uint256(0));
        IERC20(usdcAddress).safeIncreaseAllowance(
            rewardAddress,
            uint256(-1)
        );

        IERC20(wmaticAddress).safeApprove(uniRouterAddress, uint256(0));
        IERC20(wmaticAddress).safeIncreaseAllowance(
            uniRouterAddress,
            uint256(-1)
        );
    }
    
    function setSettings(
        uint256 _controllerFee,
        uint256 _rewardRate,
        uint256 _buyBackRate,
        uint256 _withdrawalFee,
        uint256 _slippageFactor,
        uint256 _liquiditySlippageFactor
    ) external virtual onlyGov {
        require(_controllerFee.add(_rewardRate).add(_buyBackRate) <= feeMaxTotal, "Max fee of 10%");
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

    function setDeadline(uint256 _deadline) external onlyGov{
        require(_deadline > 10, 'setDeadline: too small');
        emit DeadlineChanged(deadline, _deadline);
        deadline = _deadline;
    }

    function setGov(address _govAddress) external onlyGov {
        emit GovChanged(govAddress, _govAddress);
        govAddress = _govAddress;
    }
    
    function _safeSwap(
        uint256 _amountIn,
        address[] memory _path,
        address _to
    ) internal {
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

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }

    receive() external payable {}
}