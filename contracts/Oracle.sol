//SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

import "./interfaces/AggregatorV3Interface.sol";
import "./interfaces/InterestSwapPairInterface.sol";

import "./lib/ERC20Lib.sol";
import "./lib/Math.sol";
import "./lib/SafeCast.sol";

contract Oracle is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /*///////////////////////////////////////////////////////////////
                            LIBRARIES
    //////////////////////////////////////////////////////////////*/

    using SafeCastLib for int256;
    using Math for *;
    using ERC20Lib for address;

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

    /**
     * @dev It calls chainlink to get the USD price of a token and adjusts the decimals.
     *
     * @notice The amount will have 18 decimals
     *
     * @param pair The address of a pair token.
     * @param amount The number of tokens to calculate the value in USD.
     * @return price uint256 The price of the token in USD.
     */
    function getLPTokenUSDPrice(InterestSwapPairInterface pair, uint256 amount)
        public
        view
        returns (uint256 price)
    {
        uint256 totalSupply = pair.totalSupply();
        (
            address token0,
            address token1,
            ,
            ,
            uint256 reserve0,
            uint256 reserve1,
            ,

        ) = pair.metadata();

        // Get square root of K
        uint256 sqrtK = Math.sqrt(reserve0 * (reserve1)) / totalSupply;

        AggregatorV3Interface token0Feed = getUSDFeed[token0];
        AggregatorV3Interface token1Feed = getUSDFeed[token0];

        (, int256 answer0, , , ) = token0Feed.latestRoundData();
        (, int256 answer1, , , ) = token1Feed.latestRoundData();

        uint256 price0 = answer0.toUint256().toWad(token0.safeDecimals());
        uint256 price1 = answer1.toUint256().toWad(token1.safeDecimals());

        // Get fair price of LP token in USD by re-engineering the K formula.
        price = (((sqrtK * 2 * (price0.sqrt()))) * (price1.sqrt())).wadMul(
            amount
        );
    }

    /**
     * @dev It calls chainlink to get the USD price of a token and adjusts the decimals.
     *
     * @notice On the TWAP we assume 1 BUSD is 1 USD.
     * @notice The amount will have 18 decimals
     * @notice We assume that TWAP will support token/BNB as this is the most common pairing and not token/BUSD or token/USDC.
     *
     * @param token The address of the token for the feed.
     * @param amount The number of tokens to calculate the value in USD.
     * @return price uint256 The price of the token in USD.
     */
    function getTokenUSDPrice(address token, uint256 amount)
        public
        view
        returns (uint256 price)
    {
        require(token != address(0), "Oracle: no address zero");

        AggregatorV3Interface feed = getUSDFeed[token];

        (, int256 answer, , , ) = feed.latestRoundData();

        price = answer.toUint256().toWad(token.safeDecimals()).wadMul(amount);
    }

    /*///////////////////////////////////////////////////////////////
                            OWNER ONLY FUNCTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Sets a chain link {AggregatorV3Interface} USD feed for an asset.
     *
     * @param asset The token that will be associated with a feed.
     * @param feed The address of the chain link oracle contract.
     *
     * **** IMPORTANT ****
     * @notice This contract only supports tokens with 18 decimals.
     * @notice You can find the avaliable feeds here https://docs.chain.link/docs/binance-smart-chain-addresses/
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
