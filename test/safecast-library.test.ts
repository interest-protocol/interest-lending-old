import { expect } from 'chai';
import { ethers } from 'hardhat';

import { SafeCastTest } from '../typechain';
import { deploy } from './utils';

const MAX_UINT_128 = ethers.BigNumber.from(2).pow(128).sub(1);

const MAX_UINT_64 = ethers.BigNumber.from(2).pow(64).sub(1);

describe('SafeCastLib', function () {
  let sut: SafeCastTest;

  beforeEach(async () => {
    sut = await deploy('SafeCastTest', []);
  });

  it('properly casts a uint256 to uint128', async () => {
    await expect(sut.toUint128(MAX_UINT_128.add(1))).to.be.reverted;

    expect(await sut.toUint128(MAX_UINT_128)).to.be.equal(MAX_UINT_128);

    expect(await sut.toUint128(ethers.utils.parseEther('50'))).to.be.equal(
      ethers.utils.parseEther('50')
    );
  });

  it('properly casts a uint256 to uint64', async () => {
    await expect(sut.toUint64(MAX_UINT_64.add(1))).to.be.reverted;

    expect(await sut.toUint64(MAX_UINT_64)).to.be.equal(MAX_UINT_64);

    expect(await sut.toUint64(ethers.utils.parseEther('18'))).to.be.equal(
      ethers.utils.parseEther('18')
    );
  });

  it('properly casts a int256 to uint256', async () => {
    await expect(sut.toUint256(ethers.constants.MaxInt256.add(1))).to.be
      .reverted;

    await expect(sut.toUint256(-100)).to.be.reverted;

    expect(await sut.toUint256(ethers.constants.MaxInt256)).to.be.equal(
      ethers.constants.MaxInt256
    );

    expect(await sut.toUint256(ethers.utils.parseEther('18'))).to.be.equal(
      ethers.utils.parseEther('18')
    );

    expect(await sut.toUint256(0)).to.be.equal(0);
  });
});
