// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title IAttack
 * @dev 吸血鬼攻击合约接口
 */
interface IAttack {
    // ============ Events ============
    
    event Migrate(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event PoolAdded(uint256 indexed pid, address pairA, address pairB);
    event ValidPairAdded(address indexed pair);
    
    // ============ Structs ============
    
    struct UserInfo {
        uint256 amount;     // 用户迁移的 LP 代币数量
        uint256 rewardDebt; // 奖励债务
        uint256 lastBlock;  // 最后一次更新的区块
    }
    
    struct PoolInfo {
        address pairA;      // 竞争对手的池子地址
        address pairB;      // 我们的池子地址
        address token0;     // 代币0
        address token1;     // 代币1
        uint256 totalAmount; // 总迁移量
        uint256 lastRewardBlock; // 最后奖励区块
        uint256 accRewardPerShare; // 累积每股奖励
    }
    
    // ============ Core Functions ============
    
    /**
     * @dev 迁移流动性从竞争对手的池子到我们的池子
     * @param pairA 竞争对手的池子地址
     * @param amount 要迁移的LP代币数量
     * @param token0 代币0地址
     * @param token1 代币1地址
     */
    function migrate(
        address pairA,
        uint256 amount,
        address token0,
        address token1
    ) external;
    
    /**
     * @dev 领取所有累积的治理代币奖励
     */
    function claim() external;
    
    // ============ View Functions ============
    
    /**
     * @dev 查看用户在指定池子的待领取奖励
     * @param pid 池子ID
     * @param user 用户地址
     * @return 待领取的奖励数量
     */
    function pendingReward(uint256 pid, address user) external view returns (uint256);
    
    /**
     * @dev 获取池子数量
     * @return 池子总数
     */
    function poolLength() external view returns (uint256);
    
    /**
     * @dev 获取用户信息
     * @param pid 池子ID
     * @param user 用户地址
     * @return amount 用户迁移的LP代币数量
     * @return rewardDebt 奖励债务
     * @return lastBlock 最后更新区块
     */
    function getUserInfo(uint256 pid, address user) 
        external 
        view 
        returns (uint256 amount, uint256 rewardDebt, uint256 lastBlock);
    
    // ============ Admin Functions ============
    
    /**
     * @dev 添加有效的竞争对手池子地址
     * @param pair 池子地址
     */
    function addValidPair(address pair) external;
}