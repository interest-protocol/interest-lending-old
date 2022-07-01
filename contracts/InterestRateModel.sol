//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/ITokenMarketInterface.sol";

import {InterestRateVars} from "./lib/DataTypes.sol";
import "./lib/Math.sol";
import "./lib/SafeCast.sol";

contract InterestRateModel is Ownable {
    /*///////////////////////////////////////////////////////////////
                              EVENTS
    //////////////////////////////////////////////////////////////*/

    event NewInterestRateVars(
        address indexed market,
        uint64 indexed baseRatePerBlock,
        uint64 indexed multiplierPerBlock,
        uint64 jumpMultiplierPerBlock,
        uint256 kink
    );

    /*///////////////////////////////////////////////////////////////
                              LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using Math for uint256;
    using SafeCastLib for uint256;

    /*///////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice An estimation of how many blocks a blockchain produces in a year.
     *
     * @dev This number depends on which blockchain this contract is deployed on.
     */
    //solhint-disable-next-line var-name-mixedcase
    uint256 public immutable BLOCKS_PER_YEAR;

    /**
     *@notice It allows to fetch the interest rate variables related to a token.
     */
    mapping(address => InterestRateVars) public getInterestRateVars;

    /*///////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @param blocksPerYear An estimation of how many blocks a blockchain produces in a year
     */
    constructor(uint256 blocksPerYear) {
        BLOCKS_PER_YEAR = blocksPerYear;
    }

    /*///////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Calculates the borrow rate for the lending market of `token`
     *
     * @param token The address of the lending market token.
     * @param cash The avaliable liquidity in the market.
     * @param totalBorrowAmount The total amount being borrowed.
     * @param reserves Amount of tokens in the market that belongs to the reserves.
     * @return uint256 The borrow rater per block.
     *
     * @dev The return value has with a scaling factor of 1/1e18.
     */
    function getBorrowRatePerBlock(
        address token,
        uint256 cash,
        uint256 totalBorrowAmount,
        uint256 reserves
    ) external view returns (uint256) {
        return _getBorrowRatePerBlock(token, cash, totalBorrowAmount, reserves);
    }

    /**
     * @notice Calculates the supply rate for a lending market using the borrow and utilization rate.
     *
     * @param token The address of the token.
     * @param cash The avaliable liquidity to be borrowed
     * @param totalBorrowAmount The total amount being borrowed
     * @param reserves Amount of cash that belongs to the reserves.
     * @param reserveFactor The % of the interest rate that is to be used for reserves.
     * @return uint256 The supply rate per block
     *
     * @dev The return value has with a scaling factor of 1/1e18.
     */
    function getSupplyRatePerBlock(
        address token,
        uint256 cash,
        uint256 totalBorrowAmount,
        uint256 reserves,
        uint256 reserveFactor
    ) external view returns (uint256) {
        uint256 borrowRateToInvestors = _getBorrowRatePerBlock(
            token,
            cash,
            totalBorrowAmount,
            reserves
        ).wadMul(1 ether - reserveFactor);

        return
            _getUtilizationRate(cash, totalBorrowAmount, reserves).wadMul(
                borrowRateToInvestors
            );
    }

    /*///////////////////////////////////////////////////////////////
                              PRIVATE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Internal function to calculate the borrow rate for a lending market
     *
     * @param token The address of the token.
     * @param cash The avaliable liquidity to be borrowed.
     * @param totalBorrowAmount The total amount being borrowed.
     * @param reserves Amount of cash that belongs to the reserves.
     * @return uint256 The borrow rate per block
     *
     * @dev The return value has with a scaling factor of 1/1e18.
     */
    function _getBorrowRatePerBlock(
        address token,
        uint256 cash,
        uint256 totalBorrowAmount,
        uint256 reserves
    ) private view returns (uint256) {
        // Get utilization rate
        uint256 utilRate = _getUtilizationRate(
            cash,
            totalBorrowAmount,
            reserves
        );

        InterestRateVars memory vars = getInterestRateVars[token];

        // If we are below the kink threshold
        if (vars.kink >= utilRate)
            return
                utilRate.wadMul(vars.multiplierPerBlock) +
                vars.baseRatePerBlock;

        // Anything equal and below the kink is charged the normal rate
        uint256 normalRate = uint256(vars.kink).wadMul(
            vars.multiplierPerBlock
        ) + vars.baseRatePerBlock;

        // % of the utility rate that is above the threshold
        uint256 excessUtil = utilRate - vars.kink;
        return excessUtil.wadMul(vars.jumpMultiplierPerBlock) + normalRate;
    }

    /**
     * @notice Calculates the percentage of the funds that are being borrowed excluding the reserves.
     *
     * @param cash The avaliable liquidity to be borrowed
     * @param totalBorrowAmount The total amount being borrowed
     * @param reserves Amount of cash that belongs to the reserves.
     * @return uint256 The utilization percentage
     *
     * @dev The return value has with a scaling factor of 1/1e18.
     */
    function _getUtilizationRate(
        uint256 cash,
        uint256 totalBorrowAmount,
        uint256 reserves
    ) private pure returns (uint256) {
        return
            totalBorrowAmount == 0
                ? 0
                : totalBorrowAmount.wadDiv(
                    (cash + totalBorrowAmount) - reserves
                );
    }

    /*///////////////////////////////////////////////////////////////
                              ONLY OWNER
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Allows the owner to update the interest rate variables for a `token`
     *
     * @notice Some of the parameters are set per year
     *
     * @param market The address of an ITokenMarket.
     * @param baseRatePerYear The minimum rate charged per year.
     * @param multiplierPerYear The multiplier rate charged per year.
     * @param jumpMultiplierPerYear The jump rate multiplier per year.
     * @param kink The utilization rate in which the jump rate is used.
     *
     * Requirements:
     *
     * - Only the owner can update the {InterestRateVars} for a `token`.
     */
    function setInterestRateVars(
        ITokenMarketInterface market,
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink
    ) external onlyOwner {
        market.accrueMarket();
        // Convert the be per block instead of per year.
        // Convert the to uint64 for optimization.
        uint64 baseRatePerBlock = (baseRatePerYear / BLOCKS_PER_YEAR)
            .toUint64();
        uint64 multiplierPerBlock = (multiplierPerYear / BLOCKS_PER_YEAR)
            .toUint64();
        uint64 jumpMultiplierPerBlock = (jumpMultiplierPerYear /
            BLOCKS_PER_YEAR).toUint64();

        InterestRateVars memory vars = InterestRateVars(
            baseRatePerBlock,
            multiplierPerBlock,
            jumpMultiplierPerBlock,
            kink.toUint64()
        );

        // Update storage
        getInterestRateVars[address(market)] = vars;

        emit NewInterestRateVars(
            address(market),
            baseRatePerBlock,
            multiplierPerBlock,
            jumpMultiplierPerBlock,
            kink
        );
    }
}
