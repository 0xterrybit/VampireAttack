// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/Attack.sol";
import "../src/GovernanceToken.sol";
import "../src/interfaces/IAttack.sol";
import "../src/interfaces/IExternalContracts.sol";

/**
 * @title AttackForkTest
 * @dev 在真实以太坊主网环境中测试 Attack 合约
 */
contract AttackForkTest is Test {
    // 主网合约地址
    address constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    
    // SushiSwap WETH/USDC 池子
    address constant SUSHISWAP_WETH_USDC_PAIR = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
    
    // 测试用的富有地址
    address constant RICH_ADDRESS = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;
    
    Attack public attack;
    GovernanceToken public governanceToken;
    address public user;

    function setUp() public {
        user = makeAddr("user");
        vm.deal(user, 100 ether);
        
        governanceToken = new GovernanceToken();
        
        // 部署攻击合约，从 SushiSwap 迁移到 Uniswap
        attack = new Attack(
            address(governanceToken),
            SUSHISWAP_FACTORY,   // 源工厂 - 从这里抢用户
            UNISWAP_V2_FACTORY   // 目标工厂 - 迁移到这里
        );
        
        governanceToken.addMinter(address(attack));
        
        console.log("=== Fork Test Setup Complete ===");
        console.log("Block number:", block.number);
        console.log("Attack contract:", address(attack));
        console.log("GovernanceToken:", address(governanceToken));
    }

    function testForkEnvironment() public {
        console.log("=== Testing Fork Environment ===");
        
        // 验证我们在 fork 的网络上
        assertTrue(block.number > 18000000, "Should be on recent mainnet fork");
        
        // 验证真实合约存在
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(UNISWAP_V2_FACTORY)
        }
        assertTrue(codeSize > 0, "Uniswap V2 Factory should exist");
        
        assembly {
            codeSize := extcodesize(SUSHISWAP_FACTORY)
        }
        assertTrue(codeSize > 0, "SushiSwap Factory should exist");
        
        console.log("Fork environment verified");
    }

    function testRealPairVerification() public {
        console.log("=== Testing Real Pair Verification ===");
        
        // 添加 SushiSwap WETH/USDC 池子到白名单
        attack.addValidPair(SUSHISWAP_WETH_USDC_PAIR);
        
        // 测试有效池子的迁移（应该成功）
        vm.deal(user, 1 ether);
        vm.startPrank(user);
        
        // 模拟池子的 token0(), token1(), factory() 调用
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("token0()"),
            abi.encode(USDC)
        );
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("token1()"),
            abi.encode(WETH)
        );
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("factory()"),
            abi.encode(SUSHISWAP_FACTORY)
        );
        
        // 模拟 transferFrom 成功
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", user, address(attack), 1000),
            abi.encode(true)
        );
        
        // 这应该成功
        attack.migrate(SUSHISWAP_WETH_USDC_PAIR, 1000, USDC, WETH);
        
        vm.stopPrank();
        
        console.log("Real pair verification works");
    }

    function testMigrateWithRealLP() public {
        console.log("=== Testing Migration with Real LP Tokens ===");
        
        // 模拟富有账户
        vm.startPrank(RICH_ADDRESS);
        
        // 检查富有账户的 LP 代币余额
        IERC20 lpToken = IERC20(SUSHISWAP_WETH_USDC_PAIR);
        uint256 lpBalance = lpToken.balanceOf(RICH_ADDRESS);
        
        if (lpBalance > 0) {
            console.log("LP token balance:", lpBalance);
            
            // 添加 SushiSwap 池子为有效池子（用于测试）
            vm.stopPrank();
            attack.addValidPair(SUSHISWAP_WETH_USDC_PAIR);
            vm.startPrank(RICH_ADDRESS);
            
            // 批准 Attack 合约使用 LP 代币
            lpToken.approve(address(attack), lpBalance);
            
            // 执行迁移（使用少量代币进行测试）
            uint256 migrateAmount = lpBalance > 1000 ? 1000 : lpBalance;
            
            uint256 initialGTBalance = governanceToken.balanceOf(RICH_ADDRESS);
            
            attack.migrate(SUSHISWAP_WETH_USDC_PAIR, migrateAmount, WETH, USDC);
            
            // 验证用户获得了治理代币奖励
            uint256 finalGTBalance = governanceToken.balanceOf(RICH_ADDRESS);
            assertTrue(finalGTBalance > initialGTBalance, "Should receive governance tokens");
            
            console.log("Initial GT balance:", initialGTBalance);
            console.log("Final GT balance:", finalGTBalance);
            console.log("Migration with real LP tokens successful");
        } else {
            console.log("Rich address has no LP tokens, skipping migration test");
        }
        
        vm.stopPrank();
    }

    function testClaimRewardsAfterMigration() public {
        console.log("=== Testing Claim Rewards ===");
        
        // 添加有效池子
        attack.addValidPair(SUSHISWAP_WETH_USDC_PAIR);
        
        vm.startPrank(user);
        
        // 给用户一些 ETH 用于 gas
        vm.deal(user, 10 ether);
        
        // 模拟用户有一些 LP 代币 - 直接设置余额
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("balanceOf(address)", user),
            abi.encode(1000 ether)
        );
        
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", user, address(attack), 1000 ether),
            abi.encode(true)
        );
        
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("token0()"),
            abi.encode(WETH)
        );
        
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("token1()"),
            abi.encode(USDC)
        );
        
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("factory()"),
            abi.encode(SUSHISWAP_FACTORY)
        );
        
        // 执行迁移
        attack.migrate(SUSHISWAP_WETH_USDC_PAIR, 1000 ether, WETH, USDC);
        
        // 等待一些时间（模拟时间流逝）
        vm.warp(block.timestamp + 3600); // 1 小时后
        vm.roll(block.number + 100); // 增加区块数
        
        // 检查待领取奖励
        uint256 pendingReward = attack.pendingReward(0, user);
        assertTrue(pendingReward > 0, "Should have pending rewards");
        
        // 领取奖励
        uint256 initialBalance = governanceToken.balanceOf(user);
        attack.claim();
        uint256 finalBalance = governanceToken.balanceOf(user);
        
        assertTrue(finalBalance > initialBalance, "Should receive claimed rewards");
        
        console.log("Pending reward:", pendingReward);
        console.log("Claimed amount:", finalBalance - initialBalance);
        console.log("Claim rewards successful");
        
        vm.stopPrank();
    }

    function testFactoryInteraction() public {
        console.log("=== Testing Factory Interaction ===");
        
        // 测试与真实 SushiSwap Factory 的交互
        IUniswapV2Factory factory = IUniswapV2Factory(SUSHISWAP_FACTORY);
        
        // 验证池子确实来自这个工厂
        IUniswapV2Pair pairContract = IUniswapV2Pair(SUSHISWAP_WETH_USDC_PAIR);
        address pairFactory = pairContract.factory();
        assertEq(pairFactory, SUSHISWAP_FACTORY, "Pair should belong to SushiSwap factory");
        
        console.log("Factory address:", address(factory));
        console.log("Pair address:", SUSHISWAP_WETH_USDC_PAIR);
        console.log("Pair factory:", pairFactory);
        console.log("Factory interaction successful");
    }

    function testGasUsageOnMainnet() public {
        console.log("=== Testing Gas Usage on Mainnet ===");
        
        attack.addValidPair(SUSHISWAP_WETH_USDC_PAIR);
        
        vm.startPrank(user);
        vm.deal(user, 10 ether);
        
        // 模拟迁移操作的 gas 使用
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("balanceOf(address)", user),
            abi.encode(1000 ether)
        );
        
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("transferFrom(address,address,uint256)", user, address(attack), 1000 ether),
            abi.encode(true)
        );
        
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("token0()"),
            abi.encode(WETH)
        );
        
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("token1()"),
            abi.encode(USDC)
        );
        
        vm.mockCall(
            SUSHISWAP_WETH_USDC_PAIR,
            abi.encodeWithSignature("factory()"),
            abi.encode(SUSHISWAP_FACTORY)
        );
        
        uint256 gasBefore = gasleft();
        
        attack.migrate(SUSHISWAP_WETH_USDC_PAIR, 1000 ether, WETH, USDC);
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for migration:", gasUsed);
        
        // 验证 gas 使用在合理范围内
        assertTrue(gasUsed < 500000, "Migration should use less than 500k gas");
        
        vm.stopPrank();
        
        console.log("Gas usage test completed");
    }
}