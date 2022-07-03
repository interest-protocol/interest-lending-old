import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, network } from 'hardhat';

import {
  InterestRateModel,
  ITokenMarket,
  MockERC20,
  TestManager,
} from '../typechain';
import {
  advanceBlock,
  calculateInitialExchangeRateMantissa,
  deployUUPS,
  multiDeploy,
} from './utils';

const { parseEther } = ethers.utils;

const BLOCKS_PER_YEAR = 2_102_400;

const BASE_RATE_PER_YEAR = parseEther('0.02');

const MULTIPLIER_PER_YEAR = parseEther('0.1');

const JUMP_MULTIPLIER_PER_YEAR = parseEther('0.15');

const KINK = parseEther('0.7');

const INITIAL_EXCHANGE_RATE_MANTISSA = calculateInitialExchangeRateMantissa(18);

describe('ITokenMarket', () => {
  let sut: ITokenMarket;
  let asset: MockERC20;
  let interestRateModel: InterestRateModel;
  let manager: TestManager;

  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  beforeEach(async () => {
    [[owner, alice, bob], [asset, interestRateModel, manager]] =
      await Promise.all([
        ethers.getSigners(),
        multiDeploy(
          ['MockERC20', 'InterestRateModel', 'TestManager'],
          [['Bitcoin', 'BTC'], [BLOCKS_PER_YEAR], []]
        ),
      ]);

    sut = await deployUUPS('ITokenMarket', [
      asset.address,
      manager.address,
      interestRateModel.address,
    ]);

    await Promise.all([
      asset.mint(alice.address, parseEther('1000')),
      asset.mint(bob.address, parseEther('1000')),
      asset.connect(alice).approve(sut.address, ethers.constants.MaxUint256),
      asset.connect(bob).approve(sut.address, ethers.constants.MaxUint256),
      interestRateModel.setInterestRateVars(
        sut.address,
        BASE_RATE_PER_YEAR,
        MULTIPLIER_PER_YEAR,
        JUMP_MULTIPLIER_PER_YEAR,
        KINK
      ),
    ]);
  });

  it('sets the state data correctly', async () => {
    const [_manager, _asset, _interestRateModel, _reserveFactorMantissa] =
      await Promise.all([
        sut.manager(),
        sut.asset(),
        sut.interestRateModel(),
        sut.reserveFactorMantissa(),
      ]);

    expect(_manager).to.be.equal(manager.address);
    expect(_asset).to.be.equal(asset.address);
    expect(_interestRateModel).to.be.equal(interestRateModel.address);
    expect(_reserveFactorMantissa).to.be.equal(parseEther('0.20'));
  });

  describe('ERC4626 interface', () => {
    it('returns total assets managed by this market', async () => {
      await Promise.all([
        manager.setDepositAllowed(true),
        manager.setBorrowAllowed(true),
      ]);

      await sut.connect(alice).deposit(parseEther('500'), alice.address);

      await network.provider.send('evm_setAutomine', [false]);

      await sut.connect(alice).borrow(parseEther('100'), alice.address);

      // Mine TX
      await advanceBlock(ethers);
      // Accrue one block worth of interest
      await advanceBlock(ethers);
      const borrowRate = await sut.borrowRatePerBlock();

      const interestRateAccumulated = borrowRate
        .mul(parseEther('100'))
        .div(parseEther('1'));

      const value = await sut.totalAssets();

      expect(value).to.be.equal(
        parseEther('100').add(interestRateAccumulated).add(parseEther('400'))
      );

      await network.provider.send('evm_setAutomine', [true]);
    });

    it('converts assets to shares', async () => {
      expect(await sut.convertToShares(parseEther('250'))).to.be.equal(
        parseEther('250')
          .mul(parseEther('1'))
          .div(INITIAL_EXCHANGE_RATE_MANTISSA)
      );

      expect(await sut.previewDeposit(parseEther('300'))).to.be.equal(
        parseEther('300')
          .mul(parseEther('1'))
          .div(INITIAL_EXCHANGE_RATE_MANTISSA)
      );
    });

    it('converts shares to assets', async () => {
      expect(await sut.convertToAssets(parseEther('250'))).to.be.equal(
        parseEther('250')
          .mul(INITIAL_EXCHANGE_RATE_MANTISSA)
          .div(parseEther('1'))
      );

      expect(await sut.previewMint(parseEther('300'))).to.be.equal(
        parseEther('300')
          .mul(INITIAL_EXCHANGE_RATE_MANTISSA)
          .div(parseEther('1'))
      );
    });

    it('returns the maximum number that can be deposited (assets)', async () => {
      const [assetTotalSupply, sutTotalSupply] = await Promise.all([
        asset.totalSupply(),
        sut.totalSupply(),
      ]);
      expect(await sut.maxDeposit(alice.address)).to.be.equal(
        assetTotalSupply.sub(
          sutTotalSupply
            .mul(INITIAL_EXCHANGE_RATE_MANTISSA)
            .div(parseEther('1'))
        )
      );
    });

    it('returns the maximum number that can be minted (shares)', async () => {
      const [assetTotalSupply, sutTotalSupply] = await Promise.all([
        asset.totalSupply(),
        sut.totalSupply(),
      ]);

      expect(await sut.maxMint(alice.address)).to.be.equal(
        assetTotalSupply
          .mul(parseEther('1'))
          .div(INITIAL_EXCHANGE_RATE_MANTISSA)
          .sub(sutTotalSupply)
      );
    });
  });
});
