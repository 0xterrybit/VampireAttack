// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract GovernanceToken {
    string public name = "Governance Token";
    string public symbol = "GT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    
    address public admin;
    mapping(address => bool) public authorizedMinters; // 基于角色的访问控制
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    
    constructor() {
        admin = msg.sender;
    }
    
    function addMinter(address _minter) external {
        require(msg.sender == admin, 'only admin');
        require(_minter != address(0), 'invalid minter address');
        require(!authorizedMinters[_minter], 'minter already exists');
        
        authorizedMinters[_minter] = true;
        emit MinterAdded(_minter);
    }
    
    function removeMinter(address _minter) external {
        require(msg.sender == admin, 'only admin');
        require(authorizedMinters[_minter], 'minter does not exist');
        
        authorizedMinters[_minter] = false;
        emit MinterRemoved(_minter);
    }
    
    function isMinter(address _address) external view returns (bool) {
        return authorizedMinters[_address];
    }
    
    function mint(address to, uint256 amount) external {
        require(authorizedMinters[msg.sender], 'not authorized minter');
        require(to != address(0), 'invalid recipient');
        require(amount > 0, 'amount must be greater than 0');
        
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transferAdmin(address newAdmin) external {
        require(msg.sender == admin, 'only admin');
        admin = newAdmin;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, 'insufficient balance');
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, 'insufficient balance');
        require(allowance[from][msg.sender] >= amount, 'insufficient allowance');
        
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        
        emit Transfer(from, to, amount);
        return true;
    }
}