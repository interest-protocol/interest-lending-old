import { expect } from 'chai';
import { ethers } from 'hardhat';

import { MathTest } from '../typechain';
import { deploy, ONE_RAY, ONE_WAD, WAD_RAY_RATIO } from './utils';

const { parseEther } = ethers.utils;

describe('MathLib', function () {
  let sut: MathTest;

  beforeEach(async () => {
    sut = await deploy('MathTest', []);
  });

  it('properly multiplies two WADs', async () => {
    expect(await sut.wadMul(parseEther('10'), parseEther('2.5'))).to.be.equal(
      parseEther('10').mul(parseEther('2.5')).div(ONE_WAD)
    );
  });

  it('properly divides two WADs', async () => {
    expect(await sut.wadDiv(parseEther('10'), parseEther('2.5'))).to.be.equal(
      parseEther('10').mul(ONE_WAD).div(parseEther('2.5'))
    );
  });

  it('properly multiplies two RAYs', async () => {
    const x = parseEther('10').mul(ethers.BigNumber.from('1234567891'));
    const y = parseEther('10').mul(ethers.BigNumber.from('9876543211'));

    expect(await sut.rayMul(x, y)).to.be.equal(x.mul(y).div(ONE_RAY));
  });

  it('properly divides two WADs', async () => {
    const x = parseEther('10').mul(ethers.BigNumber.from('1234567891'));
    const y = parseEther('10').mul(ethers.BigNumber.from('9876543211'));

    expect(await sut.rayDiv(x, y)).to.be.equal(x.mul(ONE_RAY).div(y));
  });

  it('converts a number to WAD', async () => {
    const x = 987_654_321;

    // Adds 10 decimal houses
    expect(await sut.toWad(x, 8)).to.be.equal(parseEther('9.87654321'));

    // Does not change the number as it is a WAD
    expect(await sut.toWad(parseEther('10'), 18)).to.be.equal(parseEther('10'));

    // Overflow protection
    await expect(sut.toWad(ethers.constants.MaxUint256, 17)).to.reverted;

    // Underflow protection
    expect(await sut.toWad(10_000, 27)).to.be.equal(0);
  });

  it('converts a WAD to RAY', async () => {
    expect(await sut.wadToRay(parseEther('15.5'))).to.be.equal(
      parseEther('15.5').mul(WAD_RAY_RATIO)
    );

    // overflow protection
    await expect(
      sut.wadToRay(ethers.constants.MaxUint256.div(WAD_RAY_RATIO).add(1))
    ).to.reverted;
  });

  it('converts a RAY to WAD', async () => {
    const x = parseEther('10')
      .mul(ethers.BigNumber.from('123456789155'))
      .add(ethers.BigNumber.from('512346345')); // it will round down

    // Underflow protection
    expect(await sut.rayToWad(10_000)).to.be.equal(0);

    // Underflow protection
    expect(await sut.rayToWad(10_000)).to.be.equal(0);

    // Always rounds down
    expect(await sut.rayToWad(x)).to.be.equal(
      parseEther('10')
        .mul(ethers.BigNumber.from('123456789155'))
        .div(WAD_RAY_RATIO)
    );
  });

  it('selects the lowest value', async () => {
    expect(await sut.min(ONE_RAY, ONE_WAD)).to.be.equal(ONE_WAD);

    expect(
      await sut.min(parseEther('105.5'), parseEther('105.49'))
    ).to.be.equal(parseEther('105.49'));

    expect(await sut.min(parseEther('105.5'), parseEther('105.5'))).to.be.equal(
      parseEther('105.5')
    );
  });

  it('squares roots a number', async () => {
    expect(await sut.sqrt(ethers.BigNumber.from('82726192028263'))).to.be.equal(
      9_095_394
    );
  });

  it('multiplies and divides', async () => {
    expect(
      await sut.mulDiv(parseEther('182726'), parseEther('2918'), 10 ** 6)
    ).to.be.equal(parseEther('182726').mul(parseEther('2918')).div(1e6));
  });
});
