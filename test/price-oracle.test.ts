import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { Contract } from 'ethers';
import { ethers } from 'hardhat';

import {
  BrokenPriceFeed,
  MockERC20,
  PriceOracle,
  TestFactory,
} from '../typechain';
import {
  BTC_USD_FEED,
  deploy,
  deployUUPS,
  ETH_USD_FEED,
  multiDeploy,
} from './utils';

const { parseEther } = ethers.utils;

const APPROX_BTC_PRICE = ethers.BigNumber.from('2131310000000').mul(
  ethers.BigNumber.from(10).pow(10)
);

const APPROX_ETH_PRICE = ethers.BigNumber.from('1213420000000000000000');

describe('PriceOracle', () => {
  let oracle: PriceOracle;
  let volatilePair: Contract;
  let factory: TestFactory;
  let btc: MockERC20;
  let weth: MockERC20;
  let brokenPriceFeed: BrokenPriceFeed;

  let owner: SignerWithAddress;
  let alice: SignerWithAddress;

  beforeEach(async () => {
    [[owner, alice], [btc, weth, factory], oracle] = await Promise.all([
      ethers.getSigners(),
      multiDeploy(
        ['MockERC20', 'MockERC20', 'TestFactory'],
        [['TokenA', 'TA'], ['TokenB', 'TB'], []]
      ),
      deployUUPS('PriceOracle', []),
    ]);

    brokenPriceFeed = await deploy('BrokenPriceFeed', []);

    await factory.connect(owner).createPair(btc.address, weth.address, false);
    const volatilePairAddress = await factory.getPair(
      btc.address,
      weth.address,
      false
    );

    volatilePair = (await ethers.getContractFactory('Pair')).attach(
      volatilePairAddress
    );

    await Promise.all([
      btc.mint(alice.address, parseEther('10000')),
      weth.mint(alice.address, parseEther('5000')),
      oracle.setUSDFeed(btc.address, BTC_USD_FEED),
      oracle.setUSDFeed(weth.address, ETH_USD_FEED),
    ]);
  });

  describe('function: setUSDFeed', () => {
    it('reverts if it is not called by the owner', async () => {
      await expect(
        oracle.connect(alice).setUSDFeed(btc.address, BTC_USD_FEED)
      ).to.revertedWith('Ownable: caller is not the owner');
    });

    it('updates the price feed of a token', async () => {
      expect(await oracle.getUSDFeed(weth.address)).to.be.equal(ETH_USD_FEED);

      await oracle.connect(owner).setUSDFeed(weth.address, alice.address);

      expect(await oracle.getUSDFeed(weth.address)).to.be.equal(alice.address);
    });
  });

  describe('function: getTokenUSDPrice', () => {
    it('reverts if there is no feed or its the zero address', async () => {
      await expect(oracle.getTokenUSDPrice(ethers.constants.AddressZero, 1)).to
        .be.reverted;

      await expect(oracle.getTokenUSDPrice(btc.address, 0)).to.be.reverted;
      await expect(oracle.getTokenUSDPrice(alice.address, 1)).to.be.reverted;

      await oracle.setUSDFeed(btc.address, brokenPriceFeed.address);

      await expect(oracle.getTokenUSDPrice(alice.address, 1)).to.be.reverted;
    });

    it('returns a price based on the amount with a scaling factor of 1/1e18', async () => {
      const answer = await oracle.getTokenUSDPrice(
        btc.address,
        parseEther('1')
      );

      expect(answer).to.be.closeTo(APPROX_BTC_PRICE, parseEther('1'));

      expect(
        await oracle.getTokenUSDPrice(btc.address, parseEther('2.7'))
      ).to.be.equal(answer.mul(parseEther('2.7')).div(parseEther('1')));
    });
  });

  describe('function: getLPTokenUSDPrice', () => {
    it('reverts if the arguments are invalid', async () => {
      await expect(oracle.getLPTokenUSDPrice(ethers.constants.AddressZero, 1))
        .to.reverted;

      await expect(oracle.getLPTokenUSDPrice(btc.address, 0)).to.reverted;
    });

    it('reverts if one of the underlying tokens do not have a feed', async () => {
      await oracle.setUSDFeed(weth.address, ethers.constants.AddressZero);

      await expect(
        oracle.getLPTokenUSDPrice(volatilePair.address, parseEther('1'))
      ).to.reverted;

      await Promise.all([
        oracle.setUSDFeed(weth.address, ETH_USD_FEED),
        oracle.setUSDFeed(btc.address, ethers.constants.AddressZero),
      ]);

      await expect(
        oracle.getLPTokenUSDPrice(volatilePair.address, parseEther('1'))
      ).to.reverted;
    });

    it('reverts if any of price feeds returns zero', async () => {
      await oracle.setUSDFeed(weth.address, brokenPriceFeed.address);

      await expect(
        oracle.getLPTokenUSDPrice(volatilePair.address, parseEther('1'))
      ).to.reverted;

      await Promise.all([
        oracle.setUSDFeed(weth.address, ETH_USD_FEED),
        oracle.setUSDFeed(btc.address, brokenPriceFeed.address),
      ]);

      await expect(
        oracle.getLPTokenUSDPrice(volatilePair.address, parseEther('1'))
      ).to.reverted;
    });

    it('calculates the fair price of a LP token', async () => {
      await Promise.all([
        btc.connect(alice).transfer(volatilePair.address, parseEther('10')),
        weth.connect(alice).transfer(volatilePair.address, parseEther('173.5')),
      ]);

      await volatilePair.mint(alice.address);

      const totalSupply = await volatilePair.totalSupply();

      const ratio = parseEther('10').mul(parseEther('1')).div(totalSupply);

      const ethUSD = ratio
        .mul(parseEther('173.5'))
        .div(parseEther('1'))
        .mul(APPROX_ETH_PRICE)
        .div(parseEther('1'));

      const btcUSD = ratio
        .mul(parseEther('10'))
        .div(parseEther('1'))
        .mul(APPROX_BTC_PRICE)
        .div(parseEther('1'));

      expect(
        await oracle.getLPTokenUSDPrice(volatilePair.address, parseEther('10'))
      ).to.be.closeTo(btcUSD.add(ethUSD), parseEther('5')); // 5 dollar approx

      // @notice someone tried to trick the oracles by doubling the weth reserves
      await weth
        .connect(alice)
        .transfer(volatilePair.address, parseEther('200'));

      await volatilePair.sync();

      // @notice price remains unchanged due to Chainlink oracles
      expect(
        await oracle.getLPTokenUSDPrice(volatilePair.address, parseEther('10'))
      ).to.be.closeTo(btcUSD.add(ethUSD), parseEther('5')); // 5 dollar approx
    });
  });
});
