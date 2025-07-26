# 吸血鬼攻击智能合约项目

## 项目概述

这是一个基于Solidity的吸血鬼攻击（Vampire Attack）智能合约项目，实现了流动性迁移和奖励机制。项目包含治理代币合约和攻击合约，支持用户从其他DEX迁移流动性并获得奖励。

## 项目结构

本项目采用模块化设计，将代码分割到不同文件中，提高可读性和可维护性。

### 目录结构

```
src/
├── Attack.sol                    # 主合约实现
├── GovernanceToken.sol          # 治理代币合约
├── interfaces/                  # 接口定义
│   ├── IAttack.sol             # Attack 合约接口
│   └── IExternalContracts.sol  # 外部合约接口
├── libraries/                   # 库文件
│   ├── AttackLibrary.sol       # 工具函数库
│   └── Security.sol            # 安全相关基类
```

## 模块说明

### 1. 接口层 (interfaces/)

#### IAttack.sol
- 定义 Attack 合约的完整接口
- 包含事件、结构体和函数签名
- 提供清晰的合约 API 定义

#### IExternalContracts.sol
- 集中管理所有外部合约接口
- 包含 IERC20、IUniswapV2Factory、IUniswapV2Pair、IGovernanceToken
- 便于版本管理和接口更新

### 2. 库层 (libraries/)

#### AttackLibrary.sol
- **AttackConstants**: 定义常量和错误消息
- **AttackLibrary**: 提供工具函数
  - `requireNonZeroAddress`: 地址验证
  - `requirePositiveAmount`: 数量验证
  - `calculatePendingReward`: 奖励计算
  - `calculateAccRewardPerShare`: 累积奖励计算
  - `verifyTokenPair`: 代币对验证

#### Security.sol
- **ReentrancyGuard**: 防重入攻击
- **Ownable**: 所有权管理
- 提供安全相关的基础功能

### 3. 主合约层

#### Attack.sol
- 继承接口和安全基类
- 实现核心业务逻辑
- 使用库函数简化代码

#### GovernanceToken.sol
- 基于角色的访问控制
- 支持多个授权铸造者
- 灵活的权限管理

## 核心功能

### migrate() 函数
- 允许用户从竞争对手的池子迁移 LP 代币
- 自动创建新池子并给予额外奖励
- 使用 `_check()` 验证池子有效性

### claim() 函数
- 允许用户领取累积的治理代币奖励
- 基于迁移数量和时间计算奖励
- 防重入保护

### _check() 函数
- 内部函数验证池子地址有效性
- 支持两种验证方式：
  1. 通过 `factory()` 方法验证
  2. 通过 `getPair()` 方法验证
 
## 设计优势

1. **模块化**: 清晰的代码分离，便于维护和测试
2. **可扩展性**: 接口设计支持功能扩展
3. **可读性**: 结构化的代码组织，易于理解
4. **安全性**: 多层安全保护机制
5. **灵活性**: 基于角色的权限管理

## 使用示例

```solidity
// 部署合约
Attack attack = new Attack(factoryA, factoryB, governanceToken);

// 添加有效池子
attack.addValidPair(pairAddress);

// 用户迁移
attack.migrate(pairA, amount, token0, token1);

// 用户领取奖励
attack.claim();
```

## 项目状态

✅ **编译成功** - 所有合约编译通过  
✅ **测试通过** - 所有6个测试用例均通过  
✅ **部署脚本** - 已创建完整的部署脚本  

## 合约架构

### 1. GovernanceToken.sol
- **功能**: ERC20治理代币，支持基于角色的访问控制
- **特性**: 
  - 多个授权铸造者支持
  - 管理员可以添加/移除铸造者
  - 安全的权限控制机制
  - 完整的事件日志

### 2. Attack.sol  
- **功能**: 吸血鬼攻击主合约，管理流动性迁移和奖励分发
- **特性**:
  - 流动性池管理
  - 用户奖励计算
  - 流动性迁移功能
  - 奖励领取机制

## 测试结果

所有测试均已通过：

```
Ran 6 tests for test/Attack.t.sol:AttackTest
[PASS] testClaim() (gas: 854952)
[PASS] testGetUserInfo() (gas: 804382)  
[PASS] testGovernanceToken() (gas: 102044)
[PASS] testMigrate() (gas: 804339)
[PASS] testPendingReward() (gas: 805649)
[PASS] testPoolLength() (gas: 804393)
```

## 部署和使用

### 环境变量设置
```bash
export FACTORY_A_ADDRESS=0x...  # Factory A 地址
export FACTORY_B_ADDRESS=0x...  # Factory B 地址
export PRIVATE_KEY=0x...        # 部署者私钥
export RPC_URL=...              # RPC节点地址
```

### 部署命令
```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

### 测试命令
```bash
forge test --match-contract AttackTest -vv
```

## 合约接口

### GovernanceToken 主要接口

#### 管理员功能
- `addMinter(address _minter)` - 添加授权铸造者
- `removeMinter(address _minter)` - 移除授权铸造者
- `isMinter(address _address)` - 检查是否为授权铸造者

#### 铸造功能
- `mint(address to, uint256 amount)` - 铸造代币（仅授权铸造者）

### Attack 主要接口

#### 池子管理
- `poolLength()` - 获取池子数量
- `addPool(address _lpToken, uint256 _allocPoint)` - 添加新池子

#### 用户操作
- `migrate(uint256 _pid, uint256 _amount)` - 迁移流动性
- `claim(uint256 _pid)` - 领取奖励
- `pendingReward(uint256 _pid, address _user)` - 查看待领取奖励
- `getUserInfo(uint256 _pid, address _user)` - 获取用户信息

## 安全特性

### 基于角色的访问控制
- **多铸造者支持**: 支持多个合约或地址作为授权铸造者
- **权限分离**: 管理员负责权限管理，铸造者负责代币铸造
- **动态管理**: 可以随时添加或移除铸造者权限
- **安全检查**: 完整的输入验证和权限检查

### 其他安全措施
- 重入攻击保护
- 溢出保护（Solidity 0.8+）
- 输入验证
- 事件日志记录

## 技术特点

1. **灵活的权限系统**: 基于角色的访问控制，支持多个授权铸造者
2. **完整功能**: 实现了完整的吸血鬼攻击流程
3. **安全设计**: 多层安全检查和权限控制
4. **Gas优化**: 优化的数据结构和算法
5. **可扩展性**: 支持动态添加新的流动性池
6. **事件追踪**: 完整的事件日志系统

## 核心功能

### 1. 流动性迁移
- 用户可以将LP代币从其他DEX迁移到本协议
- 迁移时会销毁原LP代币并铸造治理代币作为奖励

### 2. 奖励机制  
- 基于时间和分配点数的奖励计算
- 支持多个池子的奖励分配
- 用户可以随时领取累积的奖励

### 3. 池子管理
- 支持添加新的LP代币池子
- 每个池子有独立的分配点数
- 灵活的奖励分配机制

### 4. 用户追踪
- 记录每个用户在每个池子中的份额
- 追踪用户的奖励债务
- 提供完整的用户信息查询

## 权限控制优势

### 相比单一铸造者的优势：
1. **灵活性**: 可以授权多个合约进行铸造
2. **可扩展性**: 未来可以轻松添加新的功能合约
3. **安全性**: 可以快速移除有问题的铸造者
4. **模块化**: 不同功能可以由不同的授权合约处理

### 使用场景：
- Attack合约：处理流动性迁移奖励
- 其他奖励合约：处理不同类型的奖励分发
- 紧急合约：在特殊情况下进行代币铸造
- 治理合约：基于投票结果进行代币分发
 