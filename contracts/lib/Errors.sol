// SPDX-License-Identifier: CC-BY-4.0
pragma solidity 0.8.15;

error InvalidAssetType();

error PriceFeedNotFound(address);

error InvalidPriceFeedAnswer(int256);

error InvalidReceiver(address);

error TransferNotAllowed();

error DepositNotAllowed();

error WithdrawNotAllowed();

error ZeroAmountNotAllowed();

error ZeroAddressNotAllowed();

error NotEnoughCash();

error InvalidBorrowRate();

error BorrowNotAllowed();

error RepayNotAllowed();

error LiquidateNotAllowed();

error InvalidLiquidator();

error SeizeNotAllowed();

error ReserveFactorOutOfBounds();

error NotAuthorized();

error NotEnoughReserves();
