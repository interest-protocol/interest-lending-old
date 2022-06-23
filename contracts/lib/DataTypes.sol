// SPDX-License-Identifier: CC-BY-4.0
pragma solidity 0.8.15;

struct InterestRateVars {
    uint64 baseRatePerBlock;
    uint64 multiplierPerBlock;
    uint64 jumpMultiplierPerBlock;
    uint64 kink;
}
