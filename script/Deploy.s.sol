// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import "../src/Attack.sol";
import "../src/GovernanceToken.sol";
import "../src/interfaces/IAttack.sol";
import "../src/interfaces/IExternalContracts.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 这些地址需要根据实际情况替换
        address factoryA = vm.envAddress("FACTORY_A_ADDRESS"); // 竞争对手的工厂地址
        address factoryB = vm.envAddress("FACTORY_B_ADDRESS"); // 我们的工厂地址
        
        // 部署治理代币
        GovernanceToken governanceToken = new GovernanceToken();
        console.log("GovernanceToken deployed at:", address(governanceToken));

        // 部署Attack合约
        Attack attack = new Attack(
            address(governanceToken),
            factoryA,
            factoryB
        );
        console.log("Attack contract deployed at:", address(attack));

        // 添加Attack合约为治理代币的授权铸造者
        governanceToken.addMinter(address(attack));
        console.log("Attack contract added as authorized minter");

        vm.stopBroadcast();
    }
}