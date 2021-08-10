// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IApeswap.sol";
import "./StrategyLPBase.sol";

contract StrategyApeswap is StrategyLPBase {
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
        earnedToWmaticPath = [address(0x005d47baba0d66083c52009271faf3f50dcc01023c), address(0x000d500b1d8e8ef31e21c99d1db9a6444d3adf1270)];        
        earnedToUsdcPath = [address(0x005d47baba0d66083c52009271faf3f50dcc01023c), address(0x002791bca1f2de4661ed88a30c99a7a9449aa84174)];
        earnedToSiriusPath = [address(0x005d47baba0d66083c52009271faf3f50dcc01023c), address(0x000d500b1d8e8ef31e21c99d1db9a6444d3adf1270), 0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D];
        earnedToToken0Path = [address(0x005d47bAbA0d66083C52009271faF3F50DCc01023C), address(0x000d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270)];
        earnedToToken1Path = [address(0x005d47bAbA0d66083C52009271faF3F50DCc01023C)];
        token0ToEarnedPath = [address(0x000d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), address(0x005d47bAbA0d66083C52009271faF3F50DCc01023C)];
        token1ToEarnedPath = [address(0x5d47bAbA0d66083C52009271faF3F50DCc01023C)];
        wmaticToToken0Path = [address(0x000d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270)];
        wmaticToToken1Path = [address(0x000d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270), address(0x005d47bAbA0d66083C52009271faF3F50DCc01023C)];

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
        IApeswap(masterChef).deposit(pid, _wantAmount, address(this));
    }

    function harvest() internal virtual override{
        IApeswap(masterChef).harvest(pid, address(this));
    }

    function unstake(uint256 _amount) internal virtual override{
        IApeswap(masterChef).withdrawAndHarvest(pid, _amount, address(this));
    } 
    function emergencyWithdraw() internal virtual override onlyGov {
        IApeswap(masterChef).emergencyWithdraw(pid, address(this));
    }   
    
    function vaultSharesTotal() public virtual override view returns (uint256) {
        (uint256 balance,) = IApeswap(masterChef).userInfo(pid, address(this));
        return balance;
    } 
}