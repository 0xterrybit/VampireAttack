// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "../src/Attack.sol";
import "../src/GovernanceToken.sol";
import "../src/interfaces/IAttack.sol";
import "../src/interfaces/IExternalContracts.sol";
import "../src/libraries/AttackLibrary.sol";

// 模拟 Uniswap V2 Factory
contract MockUniswapV2Factory {
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;
    
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'PAIR_EXISTS');
        
        pair = address(new MockUniswapV2Pair(token0, token1));
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair;
        allPairs.push(pair);
    }
}

// 模拟 Uniswap V2 Pair
contract MockUniswapV2Pair {
    address public token0;
    address public token1;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }
    
    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, 'INSUFFICIENT_BALANCE');
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, 'INSUFFICIENT_BALANCE');
        require(allowance[from][msg.sender] >= value, 'INSUFFICIENT_ALLOWANCE');
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        return true;
    }
    
    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        return true;
    }
    
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
    
    function getReserves() external view returns (uint112, uint112, uint32) {
        return (1000, 1000, uint32(block.timestamp));
    }

    function burn(address) external pure returns (uint256, uint256) {
        return (100, 100);
    }
}

// 模拟 ERC20 代币
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, 'INSUFFICIENT_BALANCE');
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, 'INSUFFICIENT_BALANCE');
        require(allowance[from][msg.sender] >= amount, 'INSUFFICIENT_ALLOWANCE');
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
    
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }
}

contract AttackTest is Test {
    Attack public attack;
    GovernanceToken public governanceToken;
    MockUniswapV2Factory public factoryA;
    MockUniswapV2Factory public factoryB;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockUniswapV2Pair public pairA;
    MockUniswapV2Pair public pairB;
    
    address public user = address(0x1);
    
    function setUp() public {
        // 部署治理代币
        governanceToken = new GovernanceToken();
        
        // 部署工厂
        factoryA = new MockUniswapV2Factory();
        factoryB = new MockUniswapV2Factory();
        
        // 部署攻击合约
        attack = new Attack(
            address(governanceToken),
            address(factoryA),
            address(factoryB)
        );
        
        // 添加Attack合约为授权铸造者
        governanceToken.addMinter(address(attack));
        
        // 部署测试代币
        tokenA = new MockERC20("Token A", "TKA");
        tokenB = new MockERC20("Token B", "TKB");
        
        // 在竞争对手工厂创建配对
        pairA = MockUniswapV2Pair(factoryA.createPair(address(tokenA), address(tokenB)));
        
        // 给用户一些 LP 代币
        pairA.mint(user, 1000e18);
        
        // 添加有效配对
        attack.addValidPair(address(pairA));
    }
    
    function testMigrate() public {
        vm.startPrank(user);
        
        // 批准攻击合约使用 LP 代币
        pairA.approve(address(attack), 100e18);
        
        // 迁移 LP 代币
        attack.migrate(address(pairA), 100e18, address(tokenA), address(tokenB));
        
        // 获取用户信息
        (uint256 amount, , uint256 lastBlock) = attack.getUserInfo(0, user);
        assertEq(amount, 100e18);
        assertEq(lastBlock, block.number);
        
        vm.stopPrank();
    }
    
    function testClaim() public {
        vm.startPrank(user);
        
        // 先迁移一些 LP 代币
        pairA.approve(address(attack), 100e18);
        attack.migrate(address(pairA), 100e18, address(tokenA), address(tokenB));
        
        // 推进一些区块
        vm.roll(block.number + 10);
        
        // 领取奖励
        attack.claim();
        
        // 检查治理代币余额
        uint256 balance = governanceToken.balanceOf(user);
        assertGt(balance, 0);
        
        vm.stopPrank();
    }
    
    function testGovernanceToken() public {
        // 测试治理代币基本功能
        assertEq(governanceToken.name(), "Governance Token");
        assertEq(governanceToken.symbol(), "GT");
        assertEq(governanceToken.decimals(), 18);
        
        // 测试铸造（通过Attack合约，因为只有授权铸造者可以铸造）
        vm.prank(address(attack));
        governanceToken.mint(user, 1000e18);
        assertEq(governanceToken.balanceOf(user), 1000e18);
        
        // 测试角色控制功能
        assertTrue(governanceToken.isMinter(address(attack)));
        assertFalse(governanceToken.isMinter(user));
        
        // 测试添加新的铸造者
        address newMinter = address(0x999);
        governanceToken.addMinter(newMinter);
        assertTrue(governanceToken.isMinter(newMinter));
        
        // 测试新铸造者可以铸造
        vm.prank(newMinter);
        governanceToken.mint(user, 500e18);
        assertEq(governanceToken.balanceOf(user), 1500e18);
        
        // 测试移除铸造者
        governanceToken.removeMinter(newMinter);
        assertFalse(governanceToken.isMinter(newMinter));
        
        // 测试被移除的铸造者无法铸造
        vm.prank(newMinter);
        vm.expectRevert("not authorized minter");
        governanceToken.mint(user, 100e18);
    }
    
    function testPendingReward() public {
        vm.startPrank(user);
        
        // 迁移 LP 代币
        pairA.approve(address(attack), 100e18);
        attack.migrate(address(pairA), 100e18, address(tokenA), address(tokenB));
        
        // 推进一些区块
        vm.roll(block.number + 5);
        
        // 检查待领取奖励
        uint256 pending = attack.pendingReward(0, user);
        assertGt(pending, 0);
        
        vm.stopPrank();
    }
    
    function testPoolLength() public {
        assertEq(attack.poolLength(), 0);
        
        vm.startPrank(user);
        pairA.approve(address(attack), 100e18);
        attack.migrate(address(pairA), 100e18, address(tokenA), address(tokenB));
        vm.stopPrank();
        
        assertEq(attack.poolLength(), 1);
    }
    
    function testGetUserInfo() public {
        vm.startPrank(user);
        
        pairA.approve(address(attack), 100e18);
        attack.migrate(address(pairA), 100e18, address(tokenA), address(tokenB));
        
        (uint256 amount, , uint256 lastBlock) = attack.getUserInfo(0, user);
        assertEq(amount, 100e18);
        assertEq(lastBlock, block.number);
        
        vm.stopPrank();
    }
}