// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// openzeppelin v3.1.0
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./libs/IStrategy.sol";
import "./Operators.sol";

contract VaultChef is Ownable, ReentrancyGuard, Operators {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
    }

    struct PoolInfo {
        string desc;// To allow easy identification on polygonscan.com
        IERC20 want; // Address of the want token.
        address strat; // Strategy address that will auto compound want tokens
    }

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    mapping(address => bool) private strats;

    event AddPool(address strat, string desc);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    /**
     * @dev Add a new want to the pool. Can only be called by the owner.
     */
    function addPool(address _strat, string memory _desc) external onlyOwner nonReentrant {
        require(!strats[_strat], "Existing strategy");
        poolInfo.push(
            PoolInfo({
                want: IERC20(IStrategy(_strat).wantAddress()),
                strat: _strat,
                desc: _desc
            })
        );
        
        strats[_strat] = true;
        emit AddPool(_strat, _desc);
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return user.shares.mul(wantLockedTotal).div(sharesTotal);
    }

    // Want tokens moved from user -> this -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt) external nonReentrant{
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        //check that balance of sender <= _amount
        uint256 balance = IERC20(pool.want).balanceOf(msg.sender);
        if(balance < _wantAmt){
            _wantAmt = balance;
        }

        if (_wantAmt > 0) {
            //for token with transfer fees
            uint256 balanceBefore = IERC20(pool.want).balanceOf(address(this));
            pool.want.safeTransferFrom(msg.sender, address(this), _wantAmt);
            uint256 balanceAfter = IERC20(pool.want).balanceOf(address(this));

            uint256 change = balanceAfter.sub(balanceBefore);
            if(_wantAmt > change){
                _wantAmt = change;
            }
			
			approve(pool.want, pool.strat, _wantAmt);
            uint256 sharesAdded = IStrategy(poolInfo[_pid].strat).deposit(_wantAmt);
            user.shares = user.shares.add(sharesAdded);
        }
        emit Deposit(msg.sender, _pid, _wantAmt);
    }

     // Want tokens moved from user -> this -> Strat (compounding)
    function withdraw(uint256 _pid, uint256 _wantAmt) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 wantLockedTotal = IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw want tokens
        uint256 balance = user.shares.mul(wantLockedTotal).div(sharesTotal);
        if (_wantAmt > balance) {
            _wantAmt = balance;
        }

        if (_wantAmt > 0) {            
            uint256 wantBalBefore = IERC20(pool.want).balanceOf(address(this));
            uint256 sharesRemoved = IStrategy(poolInfo[_pid].strat).withdraw(_wantAmt);
            uint256 wantBalAfter = IERC20(pool.want).balanceOf(address(this));

            uint256 wantBal = wantBalAfter.sub(wantBalBefore);
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }
            
            pool.want.safeTransfer(msg.sender, _wantAmt);
        }
        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    // Withdraw all your staked tokens
    function withdrawAll(uint256 _pid) external {
        withdraw(_pid, uint256(-1));
    }
	
	function approve(address tokenAddress, address spenderAddress, uint256 amount) private {
	    IERC20(tokenAddress).safeApprove(spenderAddress, uint256(0));
        IERC20(tokenAddress).safeIncreaseAllowance(
            spenderAddress,
            amount
        );
	}

    function earnPools(uint256 pidFrom, uint256 pidTo) external onlyOperator{
        uint256 len = poolInfo.length;
        if(pidTo > len){
            pidTo = len;
        }
        require(pidFrom < pidTo, 'VaultChef: Invalid pool indices');
        for (uint256 pid = pidFrom; pid < pidTo; pid++) {
            IStrategy(poolInfo[pid].strat).optimisedEarn();
        }
    }

    function earnPools(uint256[] memory pids) external onlyOperator{
        uint256 len = pids.length;
        for (uint256 i = 0; i < len; i++) {
            IStrategy(poolInfo[pids[i]].strat).optimisedEarn();
        }
    }
}