// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./GovernanceToken.sol";
import "./interfaces/IAttack.sol";
import "./interfaces/IExternalContracts.sol";
import "./libraries/AttackLibrary.sol";
import "./libraries/Security.sol";

/**
 * @title Attack
 * @dev 吸血鬼攻击主合约 - 从竞争对手DEX迁移流动性并提供奖励
 * @author VampireAttack Team
 */
contract Attack is IAttack, ReentrancyGuard, Ownable {
    using AttackLibrary for *;
    
    // ============ State Variables ============
    
    /// @dev 治理代币合约
    GovernanceToken public immutable governanceToken;
    
    /// @dev 竞争对手的工厂合约 (Factory A)
    IUniswapV2Factory public immutable factoryA;
    
    /// @dev 我们的工厂合约 (Factory B)
    IUniswapV2Factory public immutable factoryB;
    
    /// @dev 池子信息数组
    PoolInfo[] public poolInfo;
    
    /// @dev 用户信息映射 poolId => user => UserInfo
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    
    /// @dev 池子地址到池子ID的映射
    mapping(address => uint256) public pairToPoolId;
    
    /// @dev 有效的竞争对手池子地址
    mapping(address => bool) public validPairs;
    
    // ============ Constructor ============
    
    constructor(
        address _governanceToken,
        address _factoryA,
        address _factoryB
    ) {
        AttackLibrary.requireNonZeroAddress(_governanceToken);
        AttackLibrary.requireNonZeroAddress(_factoryA);
        AttackLibrary.requireNonZeroAddress(_factoryB);
        
        governanceToken = GovernanceToken(_governanceToken);
        factoryA = IUniswapV2Factory(_factoryA);
        factoryB = IUniswapV2Factory(_factoryB);
    }
    
    // ============ Core Functions ============
    
    /**
     * @inheritdoc IAttack
     */
    function migrate(
        address pairA,
        uint256 amount,
        address token0,
        address token1
    ) external override nonReentrant {
        AttackLibrary.requirePositiveAmount(amount);
        require(_check(pairA), AttackConstants.ERROR_INVALID_PAIR);
        
        // 验证代币地址匹配
        IUniswapV2Pair pair = IUniswapV2Pair(pairA);
        require(
            AttackLibrary.verifyTokenPair(pair.token0(), pair.token1(), token0, token1),
            AttackConstants.ERROR_TOKEN_MISMATCH
        );
        
        // 获取或创建池子
        uint256 pid = _getOrCreatePool(pairA, token0, token1);
        
        // 转移LP代币到合约
        require(
            IERC20(pairA).transferFrom(msg.sender, address(this), amount),
            AttackConstants.ERROR_TRANSFER_FAILED
        );
        
        // 更新池子并处理奖励
        _updatePool(pid);
        _processUserReward(pid, msg.sender);
        
        // 更新用户信息
        _updateUserInfo(pid, msg.sender, amount);
        
        emit Migrate(msg.sender, pid, amount);
    }
    
    /**
     * @inheritdoc IAttack
     */
    function claim() external override nonReentrant {
        uint256 totalPending = 0;
        
        for (uint256 pid = 0; pid < poolInfo.length; pid++) {
            UserInfo storage user = userInfo[pid][msg.sender];
            if (user.amount > 0) {
                _updatePool(pid);
                
                PoolInfo storage pool = poolInfo[pid];
                uint256 pending = AttackLibrary.calculatePendingReward(
                    user.amount,
                    pool.accRewardPerShare,
                    user.rewardDebt
                );
                
                if (pending > 0) {
                    totalPending += pending;
                    user.rewardDebt = (user.amount * pool.accRewardPerShare) / AttackConstants.REWARD_PRECISION;
                }
            }
        }
        
        if (totalPending > 0) {
            governanceToken.mint(msg.sender, totalPending);
            emit Claim(msg.sender, totalPending);
        }
    }
    
    // ============ Internal Functions ============
    
    /**
     * @dev 验证池子地址是否来自工厂A
     * @param pair 要验证的池子地址
     * @return 是否为有效的工厂A池子
     */
    function _check(address pair) internal view returns (bool) {
        // 首先检查是否在白名单中
        if (!validPairs[pair]) {
            return false;
        }
        
        // 验证池子确实来自工厂A
        try IUniswapV2Pair(pair).factory() returns (address factory) {
            return factory == address(factoryA);
        } catch {
            // 如果调用失败，尝试通过工厂验证
            try IUniswapV2Pair(pair).token0() returns (address token0) {
                try IUniswapV2Pair(pair).token1() returns (address token1) {
                    address expectedPair = factoryA.getPair(token0, token1);
                    return expectedPair == pair;
                } catch {
                    return false;
                }
            } catch {
                return false;
            }
        }
    }
    
    /**
     * @dev 获取或创建池子
     */
    function _getOrCreatePool(
        address pairA,
        address token0,
        address token1
    ) internal returns (uint256) {
        uint256 pid = pairToPoolId[pairA];
        
        // 如果池子不存在，创建新池子
        if (pid == 0 && (poolInfo.length == 0 || poolInfo[0].pairA != pairA)) {
            pid = _addPool(pairA, token0, token1);
        }
        
        return pid;
    }
    
    /**
     * @dev 添加新池子
     */
    function _addPool(
        address pairA,
        address token0,
        address token1
    ) internal returns (uint256) {
        // 检查我们的工厂中是否存在对应的池子
        address pairB = factoryB.getPair(token0, token1);
        bool isNewPair = false;
        
        if (pairB == address(0)) {
            // 创建新池子
            pairB = factoryB.createPair(token0, token1);
            isNewPair = true;
        }
        
        uint256 pid = poolInfo.length;
        poolInfo.push(PoolInfo({
            pairA: pairA,
            pairB: pairB,
            token0: token0,
            token1: token1,
            totalAmount: 0,
            lastRewardBlock: block.number,
            accRewardPerShare: 0
        }));
        
        pairToPoolId[pairA] = pid;
        
        // 如果创建了新池子，给用户额外奖励
        if (isNewPair) {
            governanceToken.mint(msg.sender, AttackConstants.PAIR_CREATION_BONUS);
        }
        
        emit PoolAdded(pid, pairA, pairB);
        return pid;
    }
    
    /**
     * @dev 更新池子奖励信息
     */
    function _updatePool(uint256 pid) internal {
        PoolInfo storage pool = poolInfo[pid];
        
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        
        if (pool.totalAmount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        
        uint256 blocks = block.number - pool.lastRewardBlock;
        pool.accRewardPerShare = AttackLibrary.calculateAccRewardPerShare(
            pool.accRewardPerShare,
            blocks,
            pool.totalAmount
        );
        pool.lastRewardBlock = block.number;
    }
    
    /**
     * @dev 处理用户奖励
     */
    function _processUserReward(uint256 pid, address user) internal {
        UserInfo storage userInfo_ = userInfo[pid][user];
        PoolInfo storage pool = poolInfo[pid];
        
        if (userInfo_.amount > 0) {
            uint256 pending = AttackLibrary.calculatePendingReward(
                userInfo_.amount,
                pool.accRewardPerShare,
                userInfo_.rewardDebt
            );
            
            if (pending > 0) {
                governanceToken.mint(user, pending);
            }
        }
    }
    
    /**
     * @dev 更新用户信息
     */
    function _updateUserInfo(uint256 pid, address user, uint256 amount) internal {
        UserInfo storage userInfo_ = userInfo[pid][user];
        PoolInfo storage pool = poolInfo[pid];
        
        userInfo_.amount += amount;
        userInfo_.lastBlock = block.number;
        userInfo_.rewardDebt = (userInfo_.amount * pool.accRewardPerShare) / AttackConstants.REWARD_PRECISION;
        
        pool.totalAmount += amount;
    }
    
    // ============ View Functions ============
    
    /**
     * @inheritdoc IAttack
     */
    function pendingReward(uint256 pid, address user) external view override returns (uint256) {
        require(pid < poolInfo.length, AttackConstants.ERROR_INVALID_PID);
        
        PoolInfo storage pool = poolInfo[pid];
        UserInfo storage userInfo_ = userInfo[pid][user];
        
        uint256 accRewardPerShare = pool.accRewardPerShare;
        
        if (block.number > pool.lastRewardBlock && pool.totalAmount != 0) {
            uint256 blocks = block.number - pool.lastRewardBlock;
            accRewardPerShare = AttackLibrary.calculateAccRewardPerShare(
                accRewardPerShare,
                blocks,
                pool.totalAmount
            );
        }
        
        return AttackLibrary.calculatePendingReward(
            userInfo_.amount,
            accRewardPerShare,
            userInfo_.rewardDebt
        );
    }
    
    /**
     * @inheritdoc IAttack
     */
    function poolLength() external view override returns (uint256) {
        return poolInfo.length;
    }
    
    /**
     * @inheritdoc IAttack
     */
    function getUserInfo(uint256 pid, address user) 
        external 
        view 
        override 
        returns (uint256 amount, uint256 rewardDebt, uint256 lastBlock) 
    {
        require(pid < poolInfo.length, AttackConstants.ERROR_INVALID_PID);
        
        UserInfo storage userInfo_ = userInfo[pid][user];
        return (userInfo_.amount, userInfo_.rewardDebt, userInfo_.lastBlock);
    }
    
    // ============ Admin Functions ============
    
    /**
     * @inheritdoc IAttack
     */
    function addValidPair(address pair) external override onlyOwner {
        AttackLibrary.requireNonZeroAddress(pair);
        validPairs[pair] = true;
        emit ValidPairAdded(pair);
    }
    
    /**
     * @dev 批量添加有效池子地址
     * @param pairs 池子地址数组
     */
    function addValidPairs(address[] calldata pairs) external onlyOwner {
        for (uint256 i = 0; i < pairs.length; i++) {
            AttackLibrary.requireNonZeroAddress(pairs[i]);
            validPairs[pairs[i]] = true;
            emit ValidPairAdded(pairs[i]);
        }
    }
    
    /**
     * @dev 移除有效池子地址
     * @param pair 池子地址
     */
    function removeValidPair(address pair) external onlyOwner {
        validPairs[pair] = false;
    }
}
