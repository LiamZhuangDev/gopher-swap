// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.31;

import {Script, console2} from "forge-std/Script.sol";

import {PoolManager} from "../src/PoolManager.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {SwapRouter} from "../src/SwapRouter.sol";

contract DeployScript is Script {
    PoolManager public poolManager;
    SwapRouter public swapRouter;
    PositionManager public positionManager;

    function run() public returns (PoolManager, SwapRouter, PositionManager) {
        uint256 deployerPrivateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));

        if (deployerPrivateKey == 0) {
            vm.startBroadcast();
        } else {
            vm.startBroadcast(deployerPrivateKey);
        }

        poolManager = new PoolManager();
        swapRouter = new SwapRouter(poolManager);
        positionManager = new PositionManager(address(poolManager));

        vm.stopBroadcast();

        console2.log("PoolManager deployed at:", address(poolManager));
        console2.log("SwapRouter deployed at:", address(swapRouter));
        console2.log("PositionManager deployed at:", address(positionManager));

        return (poolManager, swapRouter, positionManager);
    }
}
