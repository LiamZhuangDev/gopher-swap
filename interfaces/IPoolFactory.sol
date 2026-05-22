// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

interface IPoolFactory {
    function createPool(
        address tokenA,
        address tokenB,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee
    ) external returns (address pool);

    function getPool(
        address tokenA,
        address tokenB,
        uint32 index
    ) external view returns (address pool);
}