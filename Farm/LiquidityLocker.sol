// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract LiquidityLocker is Ownable {
    using SafeERC20 for IERC20;
    
    uint256 public unlockTime;
    
    constructor(
        uint256 _unlockTime
    ) public {
        unlockTime = _unlockTime;
    }

    // Return amount of token locked
    function getAmountLocked(address _token) public view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }

    //The locker must have the permission to spend the owner's token, otherwise this will fail
    function depositToken(address _token, uint256 _amount) external onlyOwner{
        require(unlockTime > block.number, "Locking time already expired!");

        uint256 balance = IERC20(_token).balanceOf(msg.sender);
        if(_amount > balance){
            _amount = balance;
        }
        
        IERC20(_token).safeTransferFrom(msg.sender,address(this),_amount);
    }

    function withdrawToken(address _token, uint256 _amount, address _to) external onlyOwner {
        require(unlockTime <= block.number, "You still need to wait!");
        
        uint256 balance = IERC20(_token).balanceOf(address(this));
        if(_amount > balance){
            _amount = balance;
        }
        IERC20(_token).safeTransfer(_to, _amount);
    }
}