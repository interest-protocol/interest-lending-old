import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { expect } from 'chai';
import { ethers, network } from 'hardhat';

import {
  MockERC20,
  TestITokenBase,
  TestITokenBaseV2,
  TestManager,
} from '../typechain';
import {
  deploy,
  deployUUPS,
  getDigest,
  getECSign,
  getPairDomainSeparator,
  multiDeploy,
  PRIVATE_KEYS,
  upgrade,
} from './utils';

const { parseEther } = ethers.utils;

describe('ITokenBase', () => {
  let sut: TestITokenBase;
  let manager: TestManager;
  let btc: MockERC20;

  let owner: SignerWithAddress;
  let alice: SignerWithAddress;
  let bob: SignerWithAddress;

  let deployedBlockNumber: number;

  beforeEach(async () => {
    [[owner, alice, bob], [btc, manager]] = await Promise.all([
      ethers.getSigners(),
      multiDeploy(['MockERC20', 'TestManager'], [['Bitcoin', 'BTC'], []]),
    ]);

    deployedBlockNumber = await ethers.provider.getBlockNumber();

    sut = await deployUUPS('TestITokenBase', [btc.address, manager.address]);

    await Promise.all([
      btc.mint(alice.address, parseEther('1000')),
      btc.connect(alice).approve(sut.address, ethers.constants.MaxUint256),
      sut.mint(alice.address, parseEther('100')),
    ]);
  });

  it('sets the state correctly', async () => {
    const chainId = network.config.chainId || 1;

    const [
      _owner,
      name,
      symbol,
      decimals,
      _manager,
      accrualBlockNumber,
      DOMAIN_SEPARATOR,
    ] = await Promise.all([
      sut.owner(),
      sut.name(),
      sut.symbol(),
      sut.decimals(),
      sut.manager(),
      sut.accrualBlockNumber(),
      sut.DOMAIN_SEPARATOR(),
    ]);

    expect(_owner).to.be.equal(owner.address);
    expect(name).to.be.equal('IBitcoin');
    expect(symbol).to.be.equal('iBTC');
    expect(decimals).to.be.equal(8);
    expect(_manager).to.be.equal(manager.address);
    expect(accrualBlockNumber.gte(deployedBlockNumber)).to.be.equal(true);
    expect(DOMAIN_SEPARATOR).to.be.equal(
      getPairDomainSeparator(sut.address, 'IBitcoin', chainId)
    );
  });

  describe('ERC20 functionality', () => {
    it('allows users to give allowance to others', async () => {
      expect(await sut.allowance(alice.address, bob.address)).to.be.equal(0);

      await expect(sut.connect(alice).approve(bob.address, 1000))
        .to.emit(sut, 'Approval')
        .withArgs(alice.address, bob.address, 1000);

      expect(await sut.allowance(alice.address, bob.address)).to.be.equal(1000);
    });

    it('reverts on {transfer} and {transferFrom} if the manager disallows', async () => {
      await expect(
        sut.connect(alice).transfer(bob.address, parseEther('10'))
      ).to.revertedWith('ITokenBase__TransferNotAllowed()');

      await sut.connect(alice).approve(bob.address, parseEther('10'));

      await expect(
        sut
          .connect(bob)
          .transferFrom(alice.address, owner.address, parseEther('5'))
      ).to.revertedWith('ITokenBase__TransferNotAllowed()');
    });

    it('reverts if a contract tries to reenter the {transfer} function', async () => {
      await manager.setTransferAllowed(true);
      const reentrancyContract = await deploy(
        'ITokenBaseERC20ReentrancyTransfer',
        [sut.address, 'Test', 'Test']
      );

      await expect(
        sut.reentrancyMint(reentrancyContract.address)
      ).to.revertedWith('ITokenBase__Reentrancy()');
    });

    it('reverts if a contract tries to reenter the {transferFrom} function', async () => {
      await manager.setTransferAllowed(true);
      const reentrancyContract = await deploy(
        'ITokenBaseERC20ReentrancyTransferFrom',
        [sut.address, 'Test', 'Test']
      );

      await expect(
        sut.reentrancyMint(reentrancyContract.address)
      ).to.revertedWith('ITokenBase__Reentrancy()');
    });

    it('allows users to transfer tokens', async () => {
      const [aliceBalance, bobBalance] = await Promise.all([
        sut.balanceOf(alice.address),
        sut.balanceOf(bob.address),
        manager.setTransferAllowed(true),
      ]);

      expect(bobBalance).to.be.equal(0);

      await expect(sut.connect(alice).transfer(bob.address, parseEther('10')))
        .to.emit(sut, 'Transfer')
        .withArgs(alice.address, bob.address, parseEther('10'));

      const [aliceBalance2, bobBalance2] = await Promise.all([
        sut.balanceOf(alice.address),
        sut.balanceOf(bob.address),
      ]);

      expect(bobBalance2).to.be.equal(parseEther('10'));
      expect(aliceBalance2).to.be.equal(aliceBalance.sub(bobBalance2));

      await expect(
        sut.connect(bob).transfer(alice.address, parseEther('10.01'))
      ).to.be.reverted;
    });

    it('allows a user to spend his/her allowance', async () => {
      await Promise.all([
        sut.connect(alice).approve(bob.address, parseEther('10')),
        manager.setTransferAllowed(true),
      ]);

      // overspend his allowance
      await expect(
        sut
          .connect(bob)
          .transferFrom(alice.address, owner.address, parseEther('10.1'))
      ).to.be.reverted;

      const [aliceBalance, ownerBalance, bobAllowance] = await Promise.all([
        sut.balanceOf(alice.address),
        sut.balanceOf(owner.address),
        sut.allowance(alice.address, bob.address),
      ]);

      expect(bobAllowance).to.be.equal(parseEther('10'));
      expect(ownerBalance).to.be.equal(0);

      await expect(
        sut
          .connect(bob)
          .transferFrom(alice.address, owner.address, parseEther('10'))
      )
        .to.emit(sut, 'Transfer')
        .withArgs(alice.address, owner.address, parseEther('10'));

      const [aliceBalance2, ownerBalance2, bobAllowance2] = await Promise.all([
        sut.balanceOf(alice.address),
        sut.balanceOf(owner.address),
        sut.allowance(alice.address, bob.address),
      ]);

      expect(bobAllowance2).to.be.equal(0);
      expect(ownerBalance2).to.be.equal(parseEther('10'));
      expect(aliceBalance2).to.be.equal(aliceBalance.sub(parseEther('10')));

      await sut
        .connect(alice)
        .approve(bob.address, ethers.constants.MaxUint256);

      await expect(
        sut
          .connect(bob)
          .transferFrom(alice.address, owner.address, parseEther('10'))
      )
        .to.emit(sut, 'Transfer')
        .withArgs(alice.address, owner.address, parseEther('10'));

      const [aliceBalance3, ownerBalance3, bobAllowance3] = await Promise.all([
        sut.balanceOf(alice.address),
        sut.balanceOf(owner.address),
        sut.allowance(alice.address, bob.address),
      ]);

      expect(bobAllowance3).to.be.equal(ethers.constants.MaxUint256);
      expect(ownerBalance3).to.be.equal(parseEther('10').add(ownerBalance2));
      expect(aliceBalance3).to.be.equal(aliceBalance2.sub(parseEther('10')));

      await expect(
        sut
          .connect(alice)
          .transferFrom(alice.address, owner.address, parseEther('10'))
      ).to.reverted;
    });

    it('reverts if the permit has expired', async () => {
      const blockTimestamp = await (
        await ethers.provider.getBlock(await ethers.provider.getBlockNumber())
      ).timestamp;

      await expect(
        sut.permit(
          alice.address,
          bob.address,
          0,
          blockTimestamp - 1,
          0,
          ethers.constants.HashZero,
          ethers.constants.HashZero
        )
      ).to.revertedWith('ITokenBase__PermitExpired()');
    });

    it('reverts if the recovered address is wrong', async () => {
      const chainId = network.config.chainId || 0;
      const name = await sut.name();
      const domainSeparator = getPairDomainSeparator(
        sut.address,
        name,
        chainId
      );

      const digest = getDigest(
        domainSeparator,
        alice.address,
        bob.address,
        parseEther('100'),
        0,
        1_700_587_613
      );

      const { v, r, s } = getECSign(PRIVATE_KEYS[1], digest);

      const bobAllowance = await sut.allowance(alice.address, bob.address);

      expect(bobAllowance).to.be.equal(0);

      await Promise.all([
        expect(
          sut
            .connect(bob)
            .permit(
              owner.address,
              bob.address,
              parseEther('100'),
              1_700_587_613,
              v,
              r,
              s
            )
        ).to.revertedWith('ITokenBase__InvalidSignature()'),
        expect(
          sut
            .connect(bob)
            .permit(
              owner.address,
              bob.address,
              parseEther('100'),
              1_700_587_613,
              0,
              ethers.constants.HashZero,
              ethers.constants.HashZero
            )
        ).to.revertedWith('ITokenBase__InvalidSignature()'),
      ]);
    });

    it('allows for permit call to give allowance', async () => {
      const chainId = network.config.chainId || 0;
      const name = await sut.name();
      const domainSeparator = getPairDomainSeparator(
        sut.address,
        name,
        chainId
      );

      const digest = getDigest(
        domainSeparator,
        alice.address,
        bob.address,
        parseEther('100'),
        0,
        1_700_587_613
      );

      const { v, r, s } = getECSign(PRIVATE_KEYS[1], digest);

      const bobAllowance = await sut.allowance(alice.address, bob.address);
      expect(bobAllowance).to.be.equal(0);

      await expect(
        sut
          .connect(bob)
          .permit(
            alice.address,
            bob.address,
            parseEther('100'),
            1_700_587_613,
            v,
            r,
            s
          )
      )
        .to.emit(sut, 'Approval')
        .withArgs(alice.address, bob.address, parseEther('100'));

      const bobAllowance2 = await sut.allowance(alice.address, bob.address);
      expect(bobAllowance2).to.be.equal(parseEther('100'));
    });
  });

  describe('Upgrade functionality', async () => {
    it('reverts if a non-developer role tries to upgrade', async () => {
      await sut.connect(owner).renounceOwnership();

      expect(upgrade(sut, 'TestITokenBaseV2')).to.revertedWith(
        'AccessControl: account 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266 is missing role 0x4504b9dfd7400a1522f49a8b4a100552da9236849581fd59b7363eb48c6a474c'
      );
    });
    it('updates to version 2', async () => {
      const aliceBalance = await sut.balanceOf(alice.address);

      const sutV2: TestITokenBaseV2 = await upgrade(sut, 'TestITokenBaseV2');

      const [version, aliceBalance2] = await Promise.all([
        sutV2.version(),
        sutV2.balanceOf(alice.address),
      ]);

      // Maintains the same state
      expect(aliceBalance2).to.be.equal(aliceBalance);
      expect(version).to.be.equal('V2');
    });
  });
});
