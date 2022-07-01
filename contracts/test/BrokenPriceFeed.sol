// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

//solhint-disable
contract BrokenPriceFeed {
    uint256 public constant decimals = 6;

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {}
}
