// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import "../interfaces/IPoolFactory.sol";
import "../interfaces/IPool.sol";
import "./Pool.sol";

contract PoolFactory is IPoolFactory {
    mapping(address => mapping(address => address[])) public pools; // token0Addr => token1Addr => pools

    Parameters public override parameters;

    function createPool(address tokenA, address tokenB, int24 tickLower, int24 tickUpper, uint24 fee)
        public
        override
        returns (address pool)
    {
        require(tokenA != tokenB, "Identical Token Address");

        address token0;
        address token1;

        (token0, token1) = sortToken(tokenA, tokenB);

        address[] memory existingPools = pools[token0][token1];

        for (uint256 i = 0; i < existingPools.length; i++) {
            IPool p = IPool(existingPools[i]);

            if (p.tickLower() == tickLower && p.tickUpper() == tickUpper && p.fee() == fee) {
                return existingPools[i];
            }
        }

        // save pool info in factory's storage for pool to read during initialization
        parameters = Parameters({
            factory: address(this), tokenA: token0, tokenB: token1, tickLower: tickLower, tickUpper: tickUpper, fee: fee
        });

        bytes32 salt = keccak256(abi.encode(token0, token1, tickLower, tickUpper, fee));
        pool = address(new Pool{salt: salt}());
        pools[token0][token1].push(pool);

        // delete pool info
        delete parameters;
    }

    function getPool(address tokenA, address tokenB, uint32 index) external view override returns (address) {
        require(tokenA != tokenB, "Identical Token Address");
        require(tokenA != address(0) && tokenB != address(0), "Zero Address");

        address token0;
        address token1;

        (token0, token1) = sortToken(tokenA, tokenB);

        return pools[token0][token1][index];
    }

    function sortToken(address tokenA, address tokenB) private pure returns (address, address) {
        return tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }
}
