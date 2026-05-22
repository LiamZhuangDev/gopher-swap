// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import "./IPoolFactory.sol";

interface IPoolManager is IPoolFactory {
    
    struct CreatePoolParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
    }

    function createPool(CreatePoolParams calldata params) external returns (address pool);

    struct PoolInfo {
        address pool;
        address token0;
        address token1;
        uint32 index;
        uint24 fee;
        uint8 feeProtocol;
        int24 tickLower;
        int24 tickUpper;
        uint160 sqrtPriceX96;
        uint128 liquidity;
    }

    function getPools() external view returns (PoolInfo[] memory pools);

    struct Pair {
        address token0;
        address token1;
    }

    function getPairs() external view returns (Pair[] memory);
}