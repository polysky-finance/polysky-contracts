// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// For interacting with PolycatFinance masterchef
interface IApeswap {
    // Transfer want tokens vault -> polycat masterchef
    function deposit(uint256 pid, uint256 _amount, address _to) external;
    
    // Transfer want tokens polycat masterchef -> vault
    function withdraw(uint256 pid, uint256 _amount, address to) external;

    //get the amount staked and reward debt for user
    function userInfo(uint256 _pid, address _address) external view returns (uint256, uint256);

    //Harvest pending rewards and send to "to"
    function harvest(uint256 pid, address to) external;

    //Emergency withdraw everything from 
    function emergencyWithdraw(uint256 pid, address to) external;

    function withdrawAndHarvest(uint256 pid, uint256 amount, address to) external;
}