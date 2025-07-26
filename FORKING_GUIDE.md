# Forking 模式测试指南

## 概述

Forking 模式允许您在本地测试环境中模拟真实的以太坊主网状态，这对于测试与现有协议的交互非常有用。

## 快速开始

### 1. 基本 Forking 测试

运行现有的 forking 测试示例：

```bash
# 使用公共 RPC 端点
forge test --fork-url https://eth.llamarpc.com --match-contract ForkTest -vv

# 或使用其他公共端点
forge test --fork-url https://rpc.ankr.com/eth --match-contract ForkTest -vv
```

### 2. Attack 合约 Forking 测试

运行 Attack 合约的 forking 测试：

```bash
forge test --fork-url https://eth.llamarpc.com --match-contract AttackForkTest -vv
```

## 测试内容

### ForkTest 基础测试
- `testForkMainnet()` - 验证 fork 环境
- `testUSDCBalance()` - 查询真实 USDC 余额
- `testImpersonateAccount()` - 模拟富有账户
- `testForkSpecificBlock()` - Fork 特定区块

### AttackForkTest 合约测试
- `testForkEnvironment()` - 验证 fork 环境设置
- `testRealPairVerification()` - 测试真实池子验证
- `testMigrateWithRealLP()` - 使用真实 LP 代币迁移
- `testClaimRewardsAfterMigration()` - 迁移后领取奖励
- `testFactoryInteraction()` - 工厂合约交互
- `testGasUsageOnMainnet()` - 主网 Gas 使用测试

## 配置选项

### 1. 使用配置文件

在 `foundry.toml` 中配置：

```toml
[profile.fork-test]
fork_url = "https://eth.llamarpc.com"
fork_block_number = 18000000  # 可选：指定区块
```

然后运行：
```bash
FOUNDRY_PROFILE=fork-test forge test --match-contract ForkTest
```

### 2. 环境变量

设置环境变量：
```bash
export ETH_RPC_URL="https://eth.llamarpc.com"
forge test --fork-url $ETH_RPC_URL --match-contract ForkTest
```

### 3. 指定区块

Fork 特定区块：
```bash
forge test --fork-url https://eth.llamarpc.com --fork-block-number 18000000 --match-contract ForkTest
```

## 真实合约地址

测试中使用的真实合约地址：

```solidity
// 工厂合约
address constant UNISWAP_V2_FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
address constant SUSHISWAP_FACTORY = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;

// 代币合约
address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC = 0xA0b86a33E6441b8C0b8b2B4B3d4B3E4B3d4B3E4B;

// 池子合约
address constant SUSHISWAP_WETH_USDC_PAIR = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;

// 富有账户（用于测试）
address constant RICH_ADDRESS = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28;
```

## 高级用法

### 1. 模拟富有账户

```solidity
function testWithRichAccount() public {
    address richUser = 0x8EB8a3b98659Cce290402893d0123abb75E3ab28;
    
    // 模拟该账户
    vm.startPrank(richUser);
    
    // 检查余额
    uint256 balance = IERC20(USDC).balanceOf(richUser);
    console.log("USDC balance:", balance);
    
    // 执行操作...
    
    vm.stopPrank();
}
```

### 2. 设置自定义状态

```solidity
function testCustomState() public {
    // 给账户提供 ETH
    vm.deal(user, 10 ether);
    
    // 模拟合约调用
    vm.mockCall(
        targetContract,
        abi.encodeWithSignature("someFunction()"),
        abi.encode(expectedReturn)
    );
    
    // 跳转到未来区块
    vm.roll(block.number + 100);
}
```

### 3. Gas 使用分析

```solidity
function testGasUsage() public {
    uint256 gasBefore = gasleft();
    
    // 执行操作
    attack.migrate(pair, amount, token0, token1);
    
    uint256 gasUsed = gasBefore - gasleft();
    console.log("Gas used:", gasUsed);
    
    // 断言 gas 使用在合理范围内
    assertLt(gasUsed, 300000, "Gas usage too high");
}
```
 