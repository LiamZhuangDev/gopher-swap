// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

interface IPool {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function tickLower() external view returns (int24);
    function tickUpper() external view returns (int24);
    function sqrtPriceX96() external view returns (uint160);
    function liquidity() external view returns (uint128);
    function initialize(uint160 sqrtPriceX96) external;
    function getPosition(address owner) external view returns (uint128 liquidity, uint256 feeGrowthInside0LastX128, uint256 feeGrowthInside1LastX128, uint128 tokensOwed0, uint128 tokensOwed1);

    function mint(
        address recipient, 
        uint128 amount, 
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);

    function burn(
        uint128 amount
    ) external returns (uint256 amount0, uint256 amount1);

    function collect(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}