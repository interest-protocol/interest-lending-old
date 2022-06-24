import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers } from 'hardhat';

import { InterestRateModel } from '../typechain';
import { deploy, USDC_ADDRESS } from './utils';

const { parseEther } = ethers.utils;

const BLOCKS_PER_YEAR = 2_102_400;

const BASE_RATE_PER_YEAR = parseEther('0.02');

const MULTIPLIER_PER_YEAR = parseEther('0.1');

const JUMP_MULTIPLIER_PER_YEAR = parseEther('0.15');

const KINK = parseEther('0.7');

describe('Interest Rate Model', () => {
  let sut: InterestRateModel;

  let owner: SignerWithAddress;
  let alice: SignerWithAddress;

  beforeEach(async () => {
    [[owner, alice], sut] = await Promise.all([
      ethers.getSigners(),
      deploy('InterestRateModel', [BLOCKS_PER_YEAR]),
    ]);

    await sut.setInterestRateVars(
      USDC_ADDRESS,
      BASE_RATE_PER_YEAR,
      MULTIPLIER_PER_YEAR,
      JUMP_MULTIPLIER_PER_YEAR,
      KINK
    );
  });

  it('updates the global variables', async () => {
    const [blocksPerYear, _owner] = await Promise.all([
      sut.BLOCKS_PER_YEAR(),
      sut.owner(),
    ]);

    expect(blocksPerYear).to.be.equal(BLOCKS_PER_YEAR);
    expect(_owner).to.be.equal(owner.address);
  });

  it('returns the borrow rate per block', async () => {
    const [result, result2, result3, variables] = await Promise.all([
      sut.getBorrowRatePerBlock(
        USDC_ADDRESS,
        parseEther('1000000'),
        0,
        parseEther('100000')
      ),
      // Will trigger the kink - 80% utilization rate
      sut.getBorrowRatePerBlock(
        USDC_ADDRESS,
        parseEther('350000'),
        parseEther('600000'),
        parseEther('200000')
      ),
      // Will NOT trigger the kink - 60% utilization rate
      sut.getBorrowRatePerBlock(
        USDC_ADDRESS,
        parseEther('600000'),
        parseEther('600000'),
        parseEther('200000')
      ),
      sut.getInterestRateVars(USDC_ADDRESS),
    ]);

    expect(result).to.be.equal(variables.baseRatePerBlock);
    expect(result2).to.be.equal(
      variables.kink
        .mul(variables.multiplierPerBlock)
        .div(parseEther('1'))
        .add(variables.baseRatePerBlock)
        .add(
          parseEther('0.8')
            .sub(variables.kink)
            .mul(variables.jumpMultiplierPerBlock)
            .div(parseEther('1'))
        )
    );
    expect(result3).to.be.equal(
      parseEther('0.6')
        .mul(variables.multiplierPerBlock)
        .div(parseEther('1'))
        .add(variables.baseRatePerBlock)
    );
  });

  it('returns the supply rate per block', async () => {
    const [result, result2, variables] = await Promise.all([
      sut.getSupplyRatePerBlock(
        USDC_ADDRESS,
        parseEther('1000000'),
        0,
        parseEther('100000'),
        parseEther('0.2')
      ),
      sut.getSupplyRatePerBlock(
        USDC_ADDRESS,
        parseEther('350000'),
        parseEther('600000'),
        parseEther('200000'),
        parseEther('0.3')
      ),
      sut.getInterestRateVars(USDC_ADDRESS),
    ]);

    // 1 - reserveFactor
    const investorFactor2 = parseEther('0.7');

    expect(result).to.be.equal(0);
    expect(result2).to.be.equal(
      parseEther('0.8')
        .mul(
          variables.kink
            .mul(variables.multiplierPerBlock)
            .div(parseEther('1'))
            .add(variables.baseRatePerBlock)
            .add(
              parseEther('0.8')
                .sub(variables.kink)
                .mul(variables.jumpMultiplierPerBlock)
                .div(parseEther('1'))
            )
            .mul(investorFactor2)
            .div(parseEther('1'))
        )
        .div(parseEther('1'))
    );
  });

  describe('function: setInterestRateVars', () => {
    it('reverts if it is called by any account other than the owner', async () => {
      await expect(
        sut.connect(alice).setInterestRateVars(USDC_ADDRESS, 0, 0, 0, 0)
      ).to.revertedWith('Ownable: caller is not the owner');
    });
    it('updates the global variables of the interest rate model', async () => {
      await expect(
        sut
          .connect(owner)
          .setInterestRateVars(
            USDC_ADDRESS,
            parseEther('0.03'),
            parseEther('0.2'),
            parseEther('0.3'),
            parseEther('0.5')
          )
      )
        .to.emit(sut, 'NewInterestRateVars')
        .withArgs(
          USDC_ADDRESS,
          parseEther('0.03').div(BLOCKS_PER_YEAR),
          parseEther('0.2').div(BLOCKS_PER_YEAR),
          parseEther('0.3').div(BLOCKS_PER_YEAR),
          parseEther('0.5')
        );
    });
  });
});
