// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// openzeppelin v3.1.0
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IMasterchef.sol";
import "./StrategyLPBase.sol";

contract StrategyKogecoin is StrategyLPBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    constructor(
        address _uniRouterAddress,      
        address _wantAddress,
        address _earnedAddress,
        address _masterChef,
        uint256 _pid,
		bool _isBurning
    ) StrategyLPBase(
        _wantAddress,
        _earnedAddress,
        _uniRouterAddress,
        _masterChef,
        _pid,
		_isBurning
    ) public {
	
	    //Only the paths, constructor arguments and possibly the masterChef interface differ for each farm
        earnedToWmaticPath = [address(0x0013748d548d95d78a3c83fe3f32604b4796cffa23), address(0x000d500b1d8e8ef31e21c99d1db9a6444d3adf1270)];        
        earnedToUsdcPath = [address(0x0013748d548d95d78a3c83fe3f32604b4796cffa23),address(0x000d500b1d8e8ef31e21c99d1db9a6444d3adf1270), address(0x002791bca1f2de4661ed88a30c99a7a9449aa84174)];
        earnedToSiriusPath = [address(0x0013748d548d95d78a3c83fe3f32604b4796cffa23), address(0x000d500b1d8e8ef31e21c99d1db9a6444d3adf1270), 0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D];
        earnedToToken0Path = [address(0x0013748d548d95d78a3c83fe3f32604b4796cffa23), address(0x000d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270)];
        earnedToToken1Path = [address(0x0013748d548d95d78a3c83fe3f32604b4796cffa23)];
        token0ToEarnedPath = [address(0x000d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), address(0x0013748d548d95d78a3c83fe3f32604b4796cffa23)];
        token1ToEarnedPath = [address(0x0013748d548d95d78a3c83fe3f32604b4796cffa23)];
        wmaticToToken0Path = [address(0x000d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270)];
        wmaticToToken1Path = [address(0x000d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), address(0x0013748d548d95d78a3c83fe3f32604b4796cffa23)];

        resetAllowances();
    }

    function resetAllowances() override public onlyGov{
        _resetAllowances();
        StrategyLPBase._resetAllowances();
        StrategyBase._resetAllowances();
        StrategyFeesBase._resetAllowances();
    }

    function _resetAllowances() internal virtual override{
    }
    
    function stake(uint256 _wantAmount) internal virtual override{
        IMasterchef(masterChef).deposit(pid, _wantAmount);
    }

    function harvest() internal virtual override{
        IMasterchef(masterChef).deposit(pid, 0);
    }

    function unstake(uint256 _amount) internal virtual override{
        IMasterchef(masterChef).withdraw(pid, _amount);
    } 
    function emergencyWithdraw() internal virtual override onlyGov {
        IMasterchef(masterChef).emergencyWithdraw(pid);
    }   
    
    function vaultSharesTotal() public virtual override view returns (uint256) {
        (uint256 balance,) = IMasterchef(masterChef).userInfo(pid, address(this));
        return balance;
    } 
}