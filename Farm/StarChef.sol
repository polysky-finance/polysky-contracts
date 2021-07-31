// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

abstract contract SiriusToken is ERC20 {
    function mint(address _to, uint256 _amount) public virtual;
}

// StarChef is the master of Sirius. He can make Sirius and he is fair.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Sirius is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract StarChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of SIRIUSes
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accSiriusPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accSiriusPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. SIRIUSes to distribute per block.
        uint256 lastRewardBlock;  // Last block number that SIRIUSes distribution occurs.
        uint256 accSiriusPerShare;   // Accumulated SIRIUSes per share, times 1e18. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
    }

    // The siriusToken address
    address public siriusAddress = 0xB1289f48E8d8Ad1532e83A8961f6E8b5a134661D;

    address public devAddress = 0x4ffE0Ee3A74CABA807E58040426431EE6d71b32D;
    address public feeAddress = 0xC5be13105b002aC1fcA10C066893be051Bbb90d3;
    address public vaultAddress = 0x3c746568A42DaB6f576B94734D0C2199b486F916;

    // SIRIUS tokens created per block.
    uint256 public siriusPerBlock = 15e16; // 0.15

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when SIRIUS mining starts.
    uint256 public startBlock = 17605000;

    //Maximum deposit fee basis point is 10%
    uint256 constant MAXIMUM_DEPOSIT_FEES = 1000;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event SetVaultAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 siriusPerBlock);

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IERC20 => bool) public poolExistence;
    modifier nonDuplicated(IERC20 _lpToken) {
        require(!poolExistence[_lpToken], "nonDuplicated: pool already exists");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IERC20 _lpToken, uint16 _depositFeeBP) external onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= MAXIMUM_DEPOSIT_FEES, "add: invalid deposit fee basis points");
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accSiriusPerShare: 0,
            depositFeeBP: _depositFeeBP
        }));
    }

    // Update the given pool's SIRIUS allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP) external onlyOwner {
        require(_depositFeeBP <= MAXIMUM_DEPOSIT_FEES, "set: invalid deposit fee basis points");
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending SIRIUSes on frontend.
    function pendingSirius(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accSiriusPerShare = pool.accSiriusPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 siriusReward = multiplier.mul(siriusPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accSiriusPerShare = accSiriusPerShare.add(siriusReward.mul(1e18).div(lpSupply));
        }
        return user.amount.mul(accSiriusPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 siriusReward = multiplier.mul(siriusPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        SiriusToken(siriusAddress).mint(devAddress, siriusReward.div(10));
        SiriusToken(siriusAddress).mint(address(this), siriusReward);
        pool.accSiriusPerShare = pool.accSiriusPerShare.add(siriusReward.mul(1e18).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to StarChef for SIRIUS allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accSiriusPerShare).div(1e18).sub(user.rewardDebt);
            if (pending > 0) {
                safeSiriusTransfer(msg.sender, pending);
            }
        }
        //check that balance of sender <= _amount
        uint256 userBalance = pool.lpToken.balanceOf(msg.sender);
        require(userBalance >= _amount, 'deposit: insufficient balance');

        if (_amount > 0) {
            //For tokens with transfer tax, check that the amount transferred is the same as the change in balance
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            uint256 balanceAfter = pool.lpToken.balanceOf(address(this));
            uint256 changeBalance = balanceAfter.sub(balanceBefore);
            
            if(changeBalance < _amount){
                _amount = changeBalance;
            }

            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);
                pool.lpToken.safeTransfer(feeAddress, depositFee.mul(3).div(10));
                pool.lpToken.safeTransfer(vaultAddress, depositFee.mul(7).div(10));
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accSiriusPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from StarChef.
    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
		
        //Check user's amount is <= requested amount
		require (_amount <= user.amount, "withdraw: insufficient balance");
        
        uint256 pending = user.amount.mul(pool.accSiriusPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            safeSiriusTransfer(msg.sender, pending);
        }

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSiriusPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe sirius transfer function, just in case if rounding error causes pool to not have enough SIRIUS.
    function safeSiriusTransfer(address _to, uint256 _amount) internal {
        uint256 siriusBal = SiriusToken(siriusAddress).balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > siriusBal) {
            transferSuccess = SiriusToken(siriusAddress).transfer(_to, siriusBal);
        } else {
            transferSuccess = SiriusToken(siriusAddress).transfer(_to, _amount);
        }
        require(transferSuccess, "safeSiriusTransfer: Transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devAddress) external onlyOwner {
        devAddress = _devAddress;
        emit SetDevAddress(msg.sender, _devAddress);
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    function setVaultAddress(address _vaultAddress) external onlyOwner {
        vaultAddress = _vaultAddress;
        emit SetVaultAddress(msg.sender, _vaultAddress);
    }
    
    function updateEmissionRate(uint256 _siriusPerBlock) external onlyOwner {
        massUpdatePools();
        siriusPerBlock = _siriusPerBlock;
        emit UpdateEmissionRate(msg.sender, _siriusPerBlock);
    }

    // Only update before start of farm
    function updateStartBlock(uint256 _startBlock) external onlyOwner {
	    require(startBlock > block.number, "Farm already started");
        require(_startBlock > block.number, "Startblock has to be in the future");
        
        startBlock = _startBlock;
        //Set the last reward block to the new start block
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            poolInfo[pid].lastRewardBlock = startBlock;
        }
    }
}
