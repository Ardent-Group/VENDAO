// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface ISpookySwap {
    function swapExactTokensForTokens(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForETH(
        uint256 _amountIn,
        uint256 _amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;

    function WETH() external returns(address);
}