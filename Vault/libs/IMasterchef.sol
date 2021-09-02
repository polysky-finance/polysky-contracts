// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// For interacting with masterchef
interface IMasterchef {
    // Transfer want tokens vault -> masterchef
    function deposit(uint256 pid, uint256 _amount) external;
    
    // Transfer want tokens masterchef -> vault
    function withdraw(uint256 pid, uint256 _amount) external;

    //get the amount staked and reward debt for user
    function userInfo(uint256 _pid, address _address) external view returns (uint256, uint256);
    
    //Emergency withdraw from the pools leaving out any pending harvest
    function emergencyWithdraw(uint256 _pid) external;
}