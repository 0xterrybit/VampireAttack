// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/Attack.sol";
import "../src/GovernanceToken.sol";

/**
 * @title RewardCalculationTest
 * @dev 专门测试奖励计算机制的准确性
 */
contract RewardCalculationTest is Test {
    Attack public attack;
    GovernanceToken public governanceToken;
    
    address public factoryA;
    address public factoryB;
    address public pair;
    address public token0;
    address public token1;
    
    address public userA;
    address public userB;
    address public userC;

    function setUp() public {
        // 创建测试用户
        userA = makeAddr("userA");
        userB = makeAddr("userB");
        userC = makeAddr("userC");
        
        // 部署模拟工厂
        factoryA = makeAddr("factoryA");
        factoryB = makeAddr("factoryB");
        
        // 创建测试代币和池子
        token0 = makeAddr("token0");
        token1 = makeAddr("token1");
        pair = makeAddr("pair");
        
        // 部署合约
        governanceToken = new GovernanceToken();
        attack = new Attack(address(governanceToken), factoryA, factoryB);
        governanceToken.addMinter(address(attack));
        
        // 添加有效池子
        attack.addValidPair(pair);
        
        // 模拟池子调用
        vm.mockCall(pair, abi.encodeWithSignature("token0()"), abi.encode(token0));
        vm.mockCall(pair, abi.encodeWithSignature("token1()"), abi.encode(token1));
        vm.mockCall(pair, abi.encodeWithSignature("factory()"), abi.encode(factoryA));
        
        // 模拟工厂调用
        vm.mockCall(factoryB, abi.encodeWithSignature("getPair(address,address)", token0, token1), abi.encode(address(0)));
        vm.mockCall(factoryB, abi.encodeWithSignature("createPair(address,address)", token0, token1), abi.encode(makeAddr("newPair")));
    }

    /**
     * @dev 测试单用户奖励计算
     */
    function testSingleUserReward() public {
        console.log("=== Single User Reward Test ===");
        
        uint256 startBlock = block.number;
        console.log("Start block:", startBlock);
        
        // 模拟转账成功
        vm.mockCall(pair, abi.encodeWithSignature("transferFrom(address,address,uint256)", userA, address(attack), 1000), abi.encode(true));
        
        // 用户A迁移1000 LP
        vm.prank(userA);
        attack.migrate(pair, 1000, token0, token1);
        
        console.log("User A migrated 1000 LP");
        
        // 检查初始状态 - 应该立即获得5 GT的创建奖励
        uint256 balance = governanceToken.balanceOf(userA);
        console.log("Balance after migration:", balance / 1e18, "GT");
        assertEq(balance, 5e18, "Should get 5 GT bonus for creating new pair");
        
        uint256 pending = attack.pendingReward(0, userA);
        console.log("Pending reward after migration:", pending);
        assertEq(pending, 0, "First migration should have no pending reward");
        
        // 前进10个区块
        vm.roll(block.number + 10);
        console.log("Advanced to block:", block.number);
        
        // 检查10个区块后的奖励
        pending = attack.pendingReward(0, userA);
        console.log("Pending reward after 10 blocks:", pending / 1e18, "GT");
        assertEq(pending, 10e18, "10 blocks should generate 10 GT reward");
        
        // 领取奖励
        vm.prank(userA);
        attack.claim();
        
        balance = governanceToken.balanceOf(userA);
        console.log("User balance after claim:", balance / 1e18, "GT");
        assertEq(balance, 15e18, "Should have 5 GT (creation bonus) + 10 GT (mining reward)");
        
        // 再前进5个区块
        vm.roll(block.number + 5);
        pending = attack.pendingReward(0, userA);
        console.log("Pending reward after 5 more blocks:", pending / 1e18, "GT");
        assertEq(pending, 5e18, "5 more blocks should generate 5 GT reward");
    }

    /**
     * @dev 测试多用户奖励分配
     */
    function testMultiUserReward() public {
        console.log("=== Multi User Reward Test ===");
        
        // 模拟转账成功
        vm.mockCall(pair, abi.encodeWithSignature("transferFrom(address,address,uint256)", userA, address(attack), 1000), abi.encode(true));
        vm.mockCall(pair, abi.encodeWithSignature("transferFrom(address,address,uint256)", userB, address(attack), 2000), abi.encode(true));
        
        // 用户A迁移1000 LP
        vm.prank(userA);
        attack.migrate(pair, 1000, token0, token1);
        console.log("User A migrated 1000 LP");
        
        // 前进10个区块
        vm.roll(block.number + 10);
        
        // 用户B迁移2000 LP
        vm.prank(userB);
        attack.migrate(pair, 2000, token0, token1);
        console.log("User B migrated 2000 LP");
        
        // 此时池子总量：3000 LP
        // 用户A占比：1000/3000 = 1/3
        // 用户B占比：2000/3000 = 2/3
        
        // 再前进6个区块
        vm.roll(block.number + 6);
        
        uint256 pendingA = attack.pendingReward(0, userA);
        uint256 pendingB = attack.pendingReward(0, userB);
        
        console.log("User A pending reward:", pendingA / 1e18, "GT");
        console.log("User B pending reward:", pendingB / 1e18, "GT");
        
        // 用户A应该得到：10 GT（前10个区块独享）+ 2 GT（后6个区块的1/3）= 12 GT
        // 用户B应该得到：4 GT（后6个区块的2/3）
        
        assertEq(pendingA, 12e18, "User A should get 12 GT");
        assertEq(pendingB, 4e18, "User B should get 4 GT");
        
        // 验证总奖励 = 总区块数 × 每区块奖励
        assertEq(pendingA + pendingB, 16e18, "Total reward should be 16 GT (16 blocks)");
    }

    /**
     * @dev 测试创建新池子奖励
     */
    function testNewPairCreationBonus() public {
        console.log("=== New Pair Creation Bonus Test ===");
        
        // 模拟转账成功
        vm.mockCall(pair, abi.encodeWithSignature("transferFrom(address,address,uint256)", userC, address(attack), 500), abi.encode(true));
        
        uint256 initialBalance = governanceToken.balanceOf(userC);
        console.log("User C initial balance:", initialBalance);
        
        // 用户C迁移LP（会触发创建新池子）
        vm.prank(userC);
        attack.migrate(pair, 500, token0, token1);
        
        uint256 afterBalance = governanceToken.balanceOf(userC);
        console.log("User C balance after migration:", afterBalance / 1e18, "GT");
        
        // 应该立即获得5 GT的创建奖励
        assertEq(afterBalance, 5e18, "Creating new pair should get 5 GT bonus");
    }

    /**
     * @dev 测试复杂场景下的奖励计算
     */
    function testComplexRewardScenario() public {
        console.log("=== Complex Reward Scenario Test ===");
        
        // 模拟转账
        vm.mockCall(pair, abi.encodeWithSignature("transferFrom(address,address,uint256)", userA, address(attack), 1000), abi.encode(true));
        vm.mockCall(pair, abi.encodeWithSignature("transferFrom(address,address,uint256)", userB, address(attack), 3000), abi.encode(true));
        vm.mockCall(pair, abi.encodeWithSignature("transferFrom(address,address,uint256)", userA, address(attack), 2000), abi.encode(true));
        
        uint256 startBlock = block.number;
        
        // 第1步：用户A迁移1000 LP（会获得5 GT创建奖励）
        vm.prank(userA);
        attack.migrate(pair, 1000, token0, token1);
        console.log("Block", block.number, ": User A migrated 1000 LP");
        
        uint256 balanceA = governanceToken.balanceOf(userA);
        console.log("User A balance after first migration:", balanceA / 1e18, "GT");
        assertEq(balanceA, 5e18, "User A should get 5 GT creation bonus");
        
        // 第2步：前进5个区块
        vm.roll(block.number + 5);
        
        // 第3步：用户B迁移3000 LP
        vm.prank(userB);
        attack.migrate(pair, 3000, token0, token1);
        console.log("Block", block.number, ": User B migrated 3000 LP");
        
        // 第4步：前进3个区块
        vm.roll(block.number + 3);
        
        // 第5步：用户A再迁移2000 LP（会立即获得前面5个区块的奖励）
        vm.prank(userA);
        attack.migrate(pair, 2000, token0, token1);
        console.log("Block", block.number, ": User A migrated 2000 more LP");
        
        // 检查用户A在第二次迁移后的余额
        balanceA = governanceToken.balanceOf(userA);
        console.log("User A balance after second migration:", balanceA / 1e18, "GT");
        // 应该有：5 GT (创建奖励) + 5 GT (前5个区块独享) + 0.75 GT (中间3个区块的1/4) = 10.75 GT
        
        // 第6步：前进2个区块
        vm.roll(block.number + 2);
        
        // 现在检查最终的待领取奖励
        uint256 pendingA = attack.pendingReward(0, userA);
        uint256 pendingB = attack.pendingReward(0, userB);
        
        console.log("User A final pending reward:", pendingA / 1e15, "mGT");
        console.log("User B final pending reward:", pendingB / 1e15, "mGT");
        
        // 用户A应该只有最后2个区块的奖励：2 × 3/6 = 1 GT
        // 用户B应该有：中间3个区块的3/4 + 最后2个区块的3/6 = 2.25 + 1 = 3.25 GT
        
        console.log("User A total balance:", balanceA / 1e18, "GT");
        console.log("User A pending reward:", pendingA / 1e18, "GT");
        console.log("User B pending reward:", pendingB / 1e18, "GT");
        
        // 验证总奖励分配正确（允许微小的精度误差）
        // 总共10个区块，每个区块1 GT，总计10 GT
        // 用户A已获得的 + 用户A待领取的 + 用户B待领取的 = 总奖励
        uint256 totalDistributed = balanceA + pendingA + pendingB;
        uint256 totalBlocks = block.number - startBlock;
        uint256 expectedTotal = totalBlocks * 1e18 + 5e18; // 包括创建奖励
        
        console.log("Total blocks:", totalBlocks);
        console.log("Total distributed (including creation bonus):", totalDistributed / 1e18, "GT");
        console.log("Expected total (including creation bonus):", expectedTotal / 1e18, "GT");
        
        // 允许最多10 wei的精度误差
        uint256 diff = totalDistributed > expectedTotal ? 
            totalDistributed - expectedTotal : 
            expectedTotal - totalDistributed;
        assertTrue(diff <= 10, "Total distributed should equal total expected rewards (within precision)");
    }
}