// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31;

import "../interfaces/IPool.sol";
import "../interfaces/IPoolFactory.sol";
import "../interfaces/IMintCallback.sol";
import "../interfaces/ISwapCallback.sol";

import "../libraries/TickMath.sol";
import "../libraries/SqrtPriceMath.sol";
import "../libraries/SwapMath.sol";
import "../libraries/FullMath.sol";
import "../libraries/FixedPoint128.sol";
import "../libraries/TransferHelper.sol";
import "../libraries/LiquidityMath.sol";
import "../libraries/LowGasSafeMath.sol";
import "../libraries/SafeCast.sol";

contract Pool is IPool {
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;

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
    int24 public override tick;
    /// @inheritdoc IPool
    uint128 public override liquidity;
    /// @inheritdoc IPool
    uint256 public override feeGrowthGlobal0X128;
    /// @inheritdoc IPool
    uint256 public override feeGrowthGlobal1X128;

    struct Position {
        uint128 liquidity;
        uint128 tokensOwed0;
        uint128 tokensOwed1;
        uint256 feeGrowthInside0LastX128;
        uint256 feeGrowthInside1LastX128;
    }

    struct ModifyPositionParams {
        address owner;
        int128 liquidityDelta;
    }

    struct SwapState {
        int256 amountSpecifiedRemaining;
        int256 amountCalculated;
        uint160 sqrtPriceX96;
        uint256 feeGrowthGlobalX128;
        uint256 amountIn;
        uint256 amountOut;
        uint256 feeAmount;
    }

    mapping(address => Position) public positions;

    constructor() {
        // IPoolFactory(msg.sender) is a type cast to the factory contract,
        // which creates this pool and initializes the pool parameters.
        (factory, token0, token1, tickLower, tickUpper, fee) = IPoolFactory(msg.sender).parameters();
    }

    function initialize(uint160 _sqrtPriceX96) external override {
        require(sqrtPriceX96 == 0, "Already initialized");
        tick = TickMath.getTickAtSqrtPrice(_sqrtPriceX96);
        require(tick >= tickLower && tick <= tickUpper, "Initial price out of range");
        sqrtPriceX96 = _sqrtPriceX96;
    }

    function _modifyPosition(ModifyPositionParams memory params)
        private
        returns (int256 amount0Delta, int256 amount1Delta)
    {
        amount0Delta = SqrtPriceMath.getAmount0Delta(
            sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickUpper), params.liquidityDelta
        );
        amount1Delta =
            SqrtPriceMath.getAmount1Delta(sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickLower), params.liquidityDelta);

        Position storage position = positions[params.owner];

        // Calculate fees owed to the position since the last modification.
        uint128 feesOwed0 = uint128(
            FullMath.mulDiv(
                feeGrowthGlobal0X128 - position.feeGrowthInside0LastX128, position.liquidity, FixedPoint128.Q128
            )
        );
        uint128 feesOwed1 = uint128(
            FullMath.mulDiv(
                feeGrowthGlobal1X128 - position.feeGrowthInside1LastX128, position.liquidity, FixedPoint128.Q128
            )
        );

        position.feeGrowthInside0LastX128 = feeGrowthGlobal0X128;
        position.feeGrowthInside1LastX128 = feeGrowthGlobal1X128;

        if (feesOwed0 > 0) {
            position.tokensOwed0 += feesOwed0;
        }
        if (feesOwed1 > 0) {
            position.tokensOwed1 += feesOwed1;
        }

        // Update the liquidity.
        liquidity = LiquidityMath.addDelta(liquidity, params.liquidityDelta);
        position.liquidity = LiquidityMath.addDelta(position.liquidity, params.liquidityDelta);
    }

    // @dev This function is used to get the balance of token0 in the pool.
    // @dev It's gas optimized to avoid a redundant extcodesize check in addition to the returndatasize check
    function _balance0() private view returns (uint256) {
        // return IERC20(token0).balanceOf(address(this));
        (bool success, bytes memory data) =
            token0.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        require(success, "Failed to get balance of token0");
        return abi.decode(data, (uint256));
    }

    // @dev This function is used to get the balance of token1 in the pool.
    // @dev It's gas optimized to avoid a redundant extcodesize check in addition to the returndatasize check
    function _balance1() private view returns (uint256) {
        // return IERC20(token1).balanceOf(address(this));
        (bool success, bytes memory data) =
            token1.staticcall(abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        require(success, "Failed to get balance of token1");
        return abi.decode(data, (uint256));
    }

    function mint(address recipient, uint128 addedLiquidity, bytes calldata data)
        external
        override
        returns (uint256 amount0, uint256 amount1)
    {
        require(addedLiquidity > 0, "Mint amount must be greater than 0");
        (int256 amount0Delta, int256 amount1Delta) =
            _modifyPosition(ModifyPositionParams({owner: recipient, liquidityDelta: int128(addedLiquidity)}));
        require(amount0Delta > 0 && amount1Delta > 0, "Invalid liquidity delta");

        amount0 = uint256(amount0Delta);
        amount1 = uint256(amount1Delta);

        uint256 balance0Before = _balance0();
        uint256 balance1Before = _balance1();

        // Call the callback to transfer tokens from the recipient to the pool.
        IMintCallback(msg.sender).mintCallback(amount0, amount1, data);

        require(balance0Before.add(amount0) <= _balance0(), "Mint callback did not transfer enough token0");
        require(balance1Before.add(amount1) <= _balance1(), "Mint callback did not transfer enough token1");
    }

    function burn(uint128 amount) external override returns (uint256 amount0, uint256 amount1) {
        require(amount > 0, "Burn amount must be greater than 0");
        require(amount <= positions[msg.sender].liquidity, "Burn amount exceeds position liquidity");

        (int256 amount0Delta, int256 amount1Delta) =
            _modifyPosition(ModifyPositionParams({owner: msg.sender, liquidityDelta: -int128(amount)}));
        require(amount0Delta < 0 && amount1Delta < 0, "Invalid liquidity delta");

        // Update the amounts owed to the position.
        amount0 = uint256(-amount0Delta);
        amount1 = uint256(-amount1Delta);
        positions[msg.sender].tokensOwed0 += uint128(amount0);
        positions[msg.sender].tokensOwed1 += uint128(amount1);
    }

    function collect(address recipient, uint128 amount0Requested, uint128 amount1Requested)
        external
        returns (uint128 amount0, uint128 amount1)
    {
        require(amount0Requested > 0 || amount1Requested > 0, "Must request at least one token");

        Position storage position = positions[msg.sender];
        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        require(amountSpecified != 0, "Amount specified must be non-zero");
        require(
            zeroForOne
                ? sqrtPriceLimitX96 < sqrtPriceX96 && sqrtPriceLimitX96 > TickMath.MIN_SQRT_PRICE
                : sqrtPriceLimitX96 > sqrtPriceX96 && sqrtPriceLimitX96 < TickMath.MAX_SQRT_PRICE,
            "Invalid price limit"
        );

        // exactInput is true if the swap is an exact input swap, meaning the amount of token0 is specified.
        // If exactInput is false, then the swap is an exact output swap, meaning the amount of token1 is specified.
        bool exactInput = amountSpecified > 0;

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: sqrtPriceX96,
            feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            amountIn: 0,
            amountOut: 0,
            feeAmount: 0
        });

        uint160 sqrtPriceX96Lower = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtPriceX96Upper = TickMath.getSqrtPriceAtTick(tickUpper);
        uint160 sqrtPriceX96PoolLimit = zeroForOne ? sqrtPriceX96Lower : sqrtPriceX96Upper;
        bool priceLimitInsidePoolLimit =
            zeroForOne ? sqrtPriceX96PoolLimit < sqrtPriceLimitX96 : sqrtPriceX96PoolLimit > sqrtPriceLimitX96;
        uint160 sqrtRatioTargetX96 = priceLimitInsidePoolLimit ? sqrtPriceLimitX96 : sqrtPriceX96PoolLimit;
        (state.sqrtPriceX96, state.amountIn, state.amountOut, state.feeAmount) =
            SwapMath.computeSwapStep(sqrtPriceX96, sqrtRatioTargetX96, liquidity, amountSpecified, fee);

        sqrtPriceX96 = state.sqrtPriceX96;
        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        state.feeGrowthGlobalX128 += FullMath.mulDiv(state.feeAmount, FixedPoint128.Q128, liquidity);
        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }

        if (exactInput) {
            state.amountSpecifiedRemaining -= (state.amountIn + state.feeAmount).toInt256();
            state.amountCalculated = state.amountCalculated.sub(state.amountOut.toInt256());
        } else {
            state.amountSpecifiedRemaining += state.amountOut.toInt256();
            state.amountCalculated = state.amountCalculated.add((state.amountIn + state.feeAmount).toInt256());
        }

        (amount0, amount1) = zeroForOne == exactInput
            ? (amountSpecified - state.amountSpecifiedRemaining, state.amountCalculated)
            : (state.amountCalculated, amountSpecified - state.amountSpecifiedRemaining);

        if (zeroForOne) {
            uint256 balance0Before = _balance0();
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            require(balance0Before.add(uint256(amount0)) <= _balance0(), "Swap callback did not transfer enough token0");
            if (amount1 < 0) {
                TransferHelper.safeTransfer(token1, recipient, uint256(-amount1));
            }
        } else {
            uint256 balance1Before = _balance1();
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            require(balance1Before.add(uint256(amount1)) <= _balance1(), "Swap callback did not transfer enough token1");
            if (amount0 < 0) {
                TransferHelper.safeTransfer(token0, recipient, uint256(-amount0));
            }
        }
    }

    function getPosition(address owner)
        external
        view
        returns (
            uint128 positionLiquidity,
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
}
