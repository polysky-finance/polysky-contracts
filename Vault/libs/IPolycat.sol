// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// For interacting with PolycatFinance masterchef
interface IPolycat {
    // Transfer want tokens vault -> polycat masterchef
    function deposit(uint256 pid, uint256 _amount, address _referrer) external;
    
    // Transfer want tokens polycat masterchef -> vault
    function withdraw(uint256 pid, uint256 _amount) external;

    //get the amount staked and reward debt for user
    function userInfo(uint256 _pid, address _address) external view returns (uint256, uint256);

    //Emergency withdraw from the pools leaving out any pending harvest
    function emergencyWithdraw(uint256 _pid) external;
}