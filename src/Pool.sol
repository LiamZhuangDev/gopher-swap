// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";

contract Pool is IPool {
    /// @inheritdoc IPool
    address public immutable override factory;
    /// @inheritdoc IPool
    address public immutable override token0;
    /// @inheritdoc IPool
    address public immutable override token1;
    /// @inheritdoc IPool
    uint24 public immutable override fee;
    /// @inheritdoc IPool
    int24 public immutable override tickLower;
    /// @inheritdoc IPool
    int24 public immutable override tickUpper;
    /// @inheritdoc IPool
    uint160 public override sqrtPriceX96;
    /// @inheritdoc IPool
    uint128 public override liquidity;

    struct Position {
        uint128 liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
    }

    mapping(address => Position) public positions;

    function initialize(uint160 _sqrtPriceX96) external override {}

    function getPosition(address owner)
        external
        view
        returns (
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        )
    {
        Position storage position = positions[owner];
        return (
            position.liquidity,
            position.feeGrowthInside0LastX128,
            position.feeGrowthInside1LastX128,
            position.tokensOwed0,
            position.tokensOwed1
        );
    }

    constructor() {
        // IPoolFactory(msg.sender) is a type cast to the factory contract,
        // which creates this pool and initializes the pool parameters.
        (factory, token0, token1, tickLower, tickUpper, fee) = IPoolFactory(msg.sender).parameters();
    }

    function mint(address recipient, uint128 amount, bytes calldata data)
        external
        override
        returns (uint256 amount0, uint256 amount1)
    {}

    function burn(uint128 amount) external override returns (uint256 amount0, uint256 amount1) {}

    function collect(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        returns (uint128 amount0, uint128 amount1)
    {}

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {}
}
