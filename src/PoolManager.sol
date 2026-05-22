// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import "../interfaces/IPoolManager.sol";
import "./PoolFactory.sol";

contract PoolManager is PoolFactory, IPoolManager {
    Pair[] public pairs;

    function getPairs() external view override returns (Pair[] memory) {
        return pairs;
    }

    function getPools() external view override returns (PoolInfo[] memory) {
        uint256 totalPools = 0;
        for (uint256 i = 0; i < pairs.length; i++) {
            totalPools += pools[pairs[i].token0][pairs[i].token1].length;
        }

        PoolInfo[] memory poolInfos = new PoolInfo[](totalPools);
        uint256 index = 0;

        for (uint256 i = 0; i < pairs.length; i++) {
            address token0 = pairs[i].token0;
            address token1 = pairs[i].token1;
            address[] memory existingPools = pools[token0][token1];

            for (uint32 j = 0; j < existingPools.length; j++) {
                IPool pool = IPool(existingPools[j]);
                poolInfos[index++] = PoolInfo({
                    pool: existingPools[j],
                    token0: token0,
                    token1: token1,
                    index: j,
                    fee: pool.fee(),
                    feeProtocol: 0,
                    tickLower: pool.tickLower(),
                    tickUpper: pool.tickUpper(),
                    sqrtPriceX96: pool.sqrtPriceX96(),
                    liquidity: pool.liquidity()
                });
            }
        }

        return poolInfos;
    }

    function createPool(CreatePoolParams calldata params) external override returns (address poolAddress) {
        require(params.token0 < params.token1, "token0 must be less than token1");

        poolAddress = super.createPool(params.token0, params.token1, params.tickLower, params.tickUpper, params.fee);
        require(poolAddress != address(0), "Failed to create pool");

        IPool pool = IPool(poolAddress);
        uint256 index = pools[pool.token0()][pool.token1()].length;

        if (index == 1) {
            pairs.push(Pair({token0: pool.token0(), token1: pool.token1()}));
        }

        if (pool.sqrtPriceX96() == 0) {
            pool.initialize(params.sqrtPriceX96);
        }
    }
}
