// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

//solhint-disable
contract TestManager {
    bool _transferAllowed;

    bool _depositAllowed;

    bool _borrowAllowed;

    function setTransferAllowed(bool value) external {
        _transferAllowed = value;
    }

    function setDepositAllowed(bool value) external {
        _depositAllowed = value;
    }

    function setBorrowAllowed(bool value) external {
        _borrowAllowed = value;
    }

    function transferAllowed(
        address,
        address,
        address,
        uint256
    ) external returns (bool) {
        return _transferAllowed;
    }

    function depositAllowed(
        address,
        address,
        address,
        uint256
    ) external returns (bool) {
        return _depositAllowed;
    }

    function withdrawAllowed(
        address iToken,
        address from,
        address to,
        uint256 assets
    ) external returns (bool) {}

    function borrowAllowed(
        address,
        address,
        address,
        uint256
    ) external returns (bool) {
        return _borrowAllowed;
    }

    function repayAllowed(
        address iToken,
        address from,
        address to,
        uint256 assets
    ) external returns (bool) {}

    function liquidateAllowed(
        address collateralMarket,
        address borrowMarket,
        address liquidator,
        address borrower,
        uint256 assets
    ) external returns (bool) {}

    function seizeAllowed(
        address collateralMarket,
        address borrowMarket,
        address liquidator,
        address borrower,
        uint256 amount
    ) external returns (bool) {}

    function liquidateCalculateSeizeTokens(
        address collateralMarket,
        address borrowMarket,
        uint256 repayAmount
    ) external returns (uint256 seizeAmount) {}
}
