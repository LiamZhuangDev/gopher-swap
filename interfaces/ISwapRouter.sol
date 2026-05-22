// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.31

interface ISwapRouter is ISwapCallback {
    struct ExactInputParams {
        address tokenIn;
        address tokenOut;
        uint32[] indexPath;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);

    struct ExactOutputParams {
        address tokenIn;
        address tokenOut;
        uint32[] indexPath;
        address recipient;
        uint256 deadline;
        uint256 amountOut;
        uint256 amountInMaximum;
        uint160 sqrtPriceLimitX96;
    }

    function exactOutput(ExactOutputParams calldata params) external payable returns (uint256 amountIn);
}