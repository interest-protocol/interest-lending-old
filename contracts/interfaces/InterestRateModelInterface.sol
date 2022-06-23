//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface InterestRateModelInterface {
    function getBorrowRatePerBlock(
        address token,
        uint256 cash,
        uint256 totalBorrowAmount,
        uint256 reserves
    ) external view returns (uint256);

    function getSupplyRatePerBlock(
        address token,
        uint256 cash,
        uint256 totalBorrowAmount,
        uint256 reserves,
        uint256 reserveFactor
    ) external view returns (uint256);
}
