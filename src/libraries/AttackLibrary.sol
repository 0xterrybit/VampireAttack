// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

/**
 * @title AttackConstants
 * @dev 吸血鬼攻击合约的常量定义
 */
library AttackConstants {
    // ============ Reward Constants ============
    
    /// @dev 每个区块的基础奖励 (1 GT)
    uint256 public constant REWARD_PER_BLOCK = 1e18;
    
    /// @dev 创建新池子的额外奖励 (5 GT)
    uint256 public constant PAIR_CREATION_BONUS = 5e18;
    
    /// @dev 奖励计算精度
    uint256 public constant REWARD_PRECISION = 1e12;
    
    // ============ Error Messages ============
    
    string public constant ERROR_ONLY_OWNER = "only owner";
    string public constant ERROR_AMOUNT_ZERO = "amount must be greater than 0";
    string public constant ERROR_INVALID_PAIR = "invalid pair from factory A";
    string public constant ERROR_TOKEN_MISMATCH = "token mismatch";
    string public constant ERROR_TRANSFER_FAILED = "transfer failed";
    string public constant ERROR_INVALID_PID = "invalid pool id";
    string public constant ERROR_ZERO_ADDRESS = "zero address";
}

/**
 * @title AttackLibrary
 * @dev 吸血鬼攻击合约的工具库
 */
library AttackLibrary {
    using AttackConstants for *;
    
    /**
     * @dev 验证地址不为零地址
     * @param addr 要验证的地址
     */
    function requireNonZeroAddress(address addr) internal pure {
        require(addr != address(0), AttackConstants.ERROR_ZERO_ADDRESS);
    }
    
    /**
     * @dev 验证数量大于零
     * @param amount 要验证的数量
     */
    function requirePositiveAmount(uint256 amount) internal pure {
        require(amount > 0, AttackConstants.ERROR_AMOUNT_ZERO);
    }
    
    /**
     * @dev 安全的数学运算 - 计算奖励
     * @param amount 用户数量
     * @param accRewardPerShare 累积每股奖励
     * @param rewardDebt 奖励债务
     * @return 待领取奖励
     */
    function calculatePendingReward(
        uint256 amount,
        uint256 accRewardPerShare,
        uint256 rewardDebt
    ) internal pure returns (uint256) {
        if (amount == 0) return 0;
        
        uint256 totalReward = (amount * accRewardPerShare) / AttackConstants.REWARD_PRECISION;
        return totalReward > rewardDebt ? totalReward - rewardDebt : 0;
    }
    
    /**
     * @dev 计算新的累积每股奖励
     * @param currentAccReward 当前累积奖励
     * @param blocks 区块数
     * @param totalAmount 总数量
     * @return 新的累积每股奖励
     */
    function calculateAccRewardPerShare(
        uint256 currentAccReward,
        uint256 blocks,
        uint256 totalAmount
    ) internal pure returns (uint256) {
        if (totalAmount == 0 || blocks == 0) return currentAccReward;
        
        uint256 reward = blocks * AttackConstants.REWARD_PER_BLOCK;
        return currentAccReward + (reward * AttackConstants.REWARD_PRECISION) / totalAmount;
    }
    
    /**
     * @dev 验证代币对是否匹配
     * @param pairToken0 池子中的token0
     * @param pairToken1 池子中的token1
     * @param token0 用户提供的token0
     * @param token1 用户提供的token1
     * @return 是否匹配
     */
    function verifyTokenPair(
        address pairToken0,
        address pairToken1,
        address token0,
        address token1
    ) internal pure returns (bool) {
        return (pairToken0 == token0 && pairToken1 == token1) ||
               (pairToken0 == token1 && pairToken1 == token0);
    }
}