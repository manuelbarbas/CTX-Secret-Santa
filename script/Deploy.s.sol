// SPDX-License-Identifier: MIT
pragma solidity >=0.8.27;

import "forge-std/Script.sol";
import "../src/SecretSanta.sol";

/**
 * @title DeployScript
 * @notice Deployment script for SecretSanta contract
 * @dev Usage: forge script script/Deploy.s.sol:DeployScript --rpc-url skale_base_sepolia --broadcast
 */
contract DeployScript is Script {
    uint256 constant DEFAULT_REGISTRATION_DURATION = 1 weeks;

    function run() external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy SecretSanta contract with 1 week registration duration
        SecretSanta secretSanta = new SecretSanta(DEFAULT_REGISTRATION_DURATION);

        console.log("=================================");
        console.log("SecretSanta deployed successfully!");
        console.log("=================================");
        console.log("Contract address:", address(secretSanta));
        console.log("Deployer address:", deployer);
        console.log("Registration duration:", DEFAULT_REGISTRATION_DURATION, "seconds");
        console.log("Chain ID:", block.chainid);
        console.log("=================================");

        vm.stopBroadcast();

        return address(secretSanta);
    }

    /**
     * @notice Deploy with custom registration duration
     * @param durationSeconds Registration period duration in seconds
     */
    function runWithCustomDuration(uint256 durationSeconds) external returns (address) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        SecretSanta secretSanta = new SecretSanta(durationSeconds);

        console.log("=================================");
        console.log("SecretSanta deployed successfully!");
        console.log("=================================");
        console.log("Contract address:", address(secretSanta));
        console.log("Deployer address:", deployer);
        console.log("Registration duration:", durationSeconds, "seconds");
        console.log("Chain ID:", block.chainid);
        console.log("=================================");

        vm.stopBroadcast();

        return address(secretSanta);
    }
}
