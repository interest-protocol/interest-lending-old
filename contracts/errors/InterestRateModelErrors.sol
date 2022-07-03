// SPDX-License-Identifier: CC-BY-4.0
pragma solidity 0.8.15;

error PriceOracle__ZeroAddressNotAllowed();

error PriceOracle__ZeroAmountNotAllowed();

error PriceOracle__InvalidAssetType();

error PriceOracle__PriceFeedNotFound(address);

error PriceOracle__InvalidPriceFeedAnswer(int256);
