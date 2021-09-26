// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IMasterchef.sol";
import "./StrategySingleBase.sol";

contract StrategySinglePolysky is StrategySingleBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    constructor(
        address _wantAddress,
        address _earnedAddress,
        address _uniRouterAddress,
        address _masterChef,
        uint256 _pid,
		bool _isBurning
    ) StrategySingleBase(
        _wantAddress,
        _earnedAddress,
        _uniRouterAddress,
        _masterChef,
        _pid,
		_isBurning
    ) public {
	
		//Only the paths, constructor arguments and possibly the masterChef interface differ for each farm
        earnedToWmaticPath = [0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D, address(0x000d500b1d8e8ef31e21c99d1db9a6444d3adf1270)];        
        earnedToUsdcPath = [0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D, address(0x002791bca1f2de4661ed88a30c99a7a9449aa84174)];
        earnedToSiriusPath = [0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D];
        earnedToWantPath= [0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D];
        wantToEarnedPath = [0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D];
    }

    function stake(uint256 _wantAmount)  internal override virtual{
        IMasterchef(masterChef).deposit(pid, _wantAmount);
    }

    function harvest() internal virtual override{
        //Masterchef has no harvest function but harvest if you try to deposit or withdraw 0 
        IMasterchef(masterChef).deposit(pid, 0);
    }

    function unstake(uint256 _amount) internal virtual override{
        IMasterchef(masterChef).withdraw(pid, _amount);
    }    

    function emergencyWithdraw() internal virtual override onlyOperator {
        IMasterchef(masterChef).emergencyWithdraw(pid);
    }
    
    function vaultSharesTotal() public virtual override view returns (uint256) {
        (uint256 amount, ) = IMasterchef(masterChef).userInfo(pid, address(this));
        return amount;
    }
}