//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "@interest-protocol/dex/interfaces/IPair.sol";

import "./errors/InterestRateModelErrors.sol";

import "./interfaces/AggregatorV3Interface.sol";

import {AssetType} from "./lib/DataTypes.sol";
import "./lib/Math.sol";
import "./lib/SafeCast.sol";
import "hardhat/console.sol";

contract PriceOracle is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /*///////////////////////////////////////////////////////////////
                            LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCastLib for int256;
    using Math for *;

    // Token Address -> Chainlink feed with USD base.
    mapping(address => AggregatorV3Interface) public getUSDFeed;

    /*///////////////////////////////////////////////////////////////
                            INITIALIZER
    //////////////////////////////////////////////////////////////*/

    /**
     * Requirements:
     *
     * - Can only be called at once and should be called during creation to prevent front running.
     */
    function initialize() external initializer {
        __Ownable_init();
    }

    /*///////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice It returns the USD price of a `token` for an `amount` with a scalar of 18.
     *
     * @param assetType It can be Normal ERC20 or Liquidity Provider Token.
     * @param token The address of the token
     * @param amount The number of tokens
     * @return uint256 The price
     *
     * @dev The function will revert if Chainlink returns a 0 value or the `assetType` is invalid.
     */
    function getAssetPrice(
        AssetType assetType,
        address token,
        uint256 amount
    ) external view returns (uint256) {
        if (token == address(0)) revert PriceOracle__ZeroAddressNotAllowed();

        if (0 == amount) revert PriceOracle__ZeroAmountNotAllowed();

        if (assetType == AssetType.Standard)
            return _getTokenUSDPrice(token, amount);

        if (assetType == AssetType.LP)
            return _getLPTokenUSDPrice(IPair(token), amount);

        //solhint-disable-next-line reason-string
        revert PriceOracle__InvalidAssetType();
    }

    /*///////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice It calculates the price of USD of a `pair` token for an `amount` based on an fair price from Chainlink.
     *
     * @param pair The address of a pair token.
     * @param amount The number of tokens to calculate the value in USD.
     * @return price uint256 The price of the token in USD.
     *
     * @dev It reverts if Chainlink returns a price equal or lower than 0. It also returns the value with a scaling factor of 1/1e18.
     */
    function _getLPTokenUSDPrice(IPair pair, uint256 amount)
        internal
        view
        returns (uint256 price)
    {
        (
            address token0,
            address token1,
            ,
            ,
            uint256 reserve0,
            uint256 reserve1,
            ,

        ) = pair.metadata();

        AggregatorV3Interface token0Feed = _safePriceFeed(token0);
        AggregatorV3Interface token1Feed = _safePriceFeed(token1);

        uint256 price0 = _safePriceFeedAnswer(token0Feed).toUint256().toWad(
            token0Feed.decimals()
        );

        uint256 price1 = _safePriceFeedAnswer(token1Feed).toUint256().toWad(
            token1Feed.decimals()
        );

        /// @dev If total supply is zero it should throw and revert
        // Get square root of K
        uint256 sqrtK = Math.sqrt(reserve0 * (reserve1)) / pair.totalSupply();

        // Get fair price of LP token in USD by re-engineering the K formula.
        price = (((sqrtK * 2 * (price0.sqrt()))) * (price1.sqrt())).wadMul(
            amount
        );
    }

    /**
     * @notice It returns the USD value of a token for an `amount`.
     *
     * @param token The address of the token.
     * @param amount The number of tokens to calculate the value in USD.
     * @return price uint256 The price of the token in USD.
     *
     * @dev The return value has a scaling factor of 1/1e18. It will revert if Chainlink returns a value equal or lower than zero.
     */
    function _getTokenUSDPrice(address token, uint256 amount)
        internal
        view
        returns (uint256 price)
    {
        AggregatorV3Interface feed = _safePriceFeed(token);

        price = _safePriceFeedAnswer(feed)
            .toUint256()
            .toWad(feed.decimals())
            .wadMul(amount);
    }

    function _safePriceFeed(address token)
        internal
        view
        returns (AggregatorV3Interface feed)
    {
        if (address(feed = getUSDFeed[token]) == address(0))
            revert PriceOracle__PriceFeedNotFound(token);
    }

    function _safePriceFeedAnswer(AggregatorV3Interface feed)
        internal
        view
        returns (int256 answer)
    {
        (, answer, , , ) = feed.latestRoundData();

        if (answer <= 0) revert PriceOracle__InvalidPriceFeedAnswer(answer);
    }

    /*///////////////////////////////////////////////////////////////
                            OWNER ONLY FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice It allows the {owner} to update the price feed for an `asset`.
     *
     * @param asset The token that will be associated with the feed.
     * @param feed The address of the chain link oracle contract.
     *
     * Requirements:
     *
     * - This function has the modifier {onlyOwner} because the whole protocol depends on the quality and veracity of these feeds. It will be behind a multisig and timelock as soon as possible.
     */
    function setUSDFeed(address asset, AggregatorV3Interface feed)
        external
        onlyOwner
    {
        getUSDFeed[asset] = feed;
    }

    /**
     * @dev A hook to guard the address that can update the implementation of this contract. It must be the owner.
     */
    function _authorizeUpgrade(address)
        internal
        view
        override
        onlyOwner
    //solhint-disable-next-line no-empty-blocks
    {

    }
}
