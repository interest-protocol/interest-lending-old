/* eslint-disable  @typescript-eslint/no-explicit-any */
// eslint-disable-next-line node/no-unpublished-import
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { ContractAddressOrInstance } from '@openzeppelin/hardhat-upgrades/dist/utils';
import { ecsign } from 'ethereumjs-util';
import { BigNumber } from 'ethers';
import { ethers, network, upgrades } from 'hardhat';

export const ONE_RAY = ethers.BigNumber.from(10).pow(27);

export const ONE_WAD = ethers.BigNumber.from(10).pow(18);

export const WAD_RAY_RATIO = ethers.BigNumber.from(10).pow(9);

// @desc follow the same order of the signers accounts
export const PRIVATE_KEYS = [
  '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80',
  '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d',
  '0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a',
];

export const impersonate = async (
  address: string
): Promise<SignerWithAddress> => {
  await network.provider.request({
    method: 'hardhat_impersonateAccount',
    params: [address],
  });

  return ethers.getSigner(address);
};

export const multiDeploy = async (
  x: ReadonlyArray<string>,
  y: Array<Array<unknown> | undefined> = []
): Promise<any> => {
  const contractFactories = await Promise.all(
    x.map((name) => ethers.getContractFactory(name))
  );

  return Promise.all(
    contractFactories.map((factory, index) =>
      factory.deploy(...(y[index] || []))
    )
  );
};

export const deploy = async (
  name: string,
  parameters: Array<unknown> = []
): Promise<any> => {
  const factory = await ethers.getContractFactory(name);
  return await factory.deploy(...parameters);
};

export const deployUUPS = async (
  name: string,
  parameters: Array<unknown> = []
): Promise<any> => {
  const factory = await ethers.getContractFactory(name);
  const instance = await upgrades.deployProxy(factory, parameters, {
    kind: 'uups',
  });
  await instance.deployed();
  return instance;
};

export const multiDeployUUPS = async (
  name: ReadonlyArray<string>,
  parameters: Array<Array<unknown> | undefined> = []
): Promise<any> => {
  const factories = await Promise.all(
    name.map((x) => ethers.getContractFactory(x))
  );

  const instances = await Promise.all(
    factories.map((factory, index) =>
      upgrades.deployProxy(factory, parameters[index], { kind: 'uups' })
    )
  );

  await Promise.all([instances.map((x) => x.deployed())]);

  return instances;
};

export const upgrade = async (
  proxy: ContractAddressOrInstance,
  name: string
): Promise<any> => {
  const factory = await ethers.getContractFactory(name);
  return upgrades.upgradeProxy(proxy, factory);
};

export const advanceTime = (
  time: number,
  _ethers: typeof ethers
): Promise<void> => _ethers.provider.send('evm_increaseTime', [time]);

export const advanceBlock = (_ethers: typeof ethers): Promise<void> =>
  _ethers.provider.send('evm_mine', []);

export const advanceBlockAndTime = async (
  time: number,
  _ethers: typeof ethers
): Promise<void> => {
  await _ethers.provider.send('evm_increaseTime', [time]);
  await _ethers.provider.send('evm_mine', []);
};

// Constants

export const USDC_ADDRESS = ethers.utils.getAddress(
  '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
);

// Chainlink Feeds

export const ETH_USD_FEED = ethers.utils.getAddress(
  '0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419'
);

export const BTC_USD_FEED = ethers.utils.getAddress(
  '0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c'
);

export enum AssetType {
  LP,
  InterestBearing,
  Standard,
}

//  EIP-2612 Logic

export const getPairDomainSeparator = (
  address: string,
  name: string,
  chainId: number
) =>
  ethers.utils.solidityKeccak256(
    ['bytes'],
    [
      ethers.utils.defaultAbiCoder.encode(
        ['bytes32', 'bytes32', 'bytes32', 'uint256', 'address'],
        [
          ethers.utils.solidityKeccak256(
            ['bytes'],
            [
              ethers.utils.toUtf8Bytes(
                'EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'
              ),
            ]
          ),
          ethers.utils.solidityKeccak256(
            ['bytes'],
            [ethers.utils.toUtf8Bytes(name)]
          ),
          ethers.utils.solidityKeccak256(
            ['bytes'],
            [ethers.utils.toUtf8Bytes('1')]
          ),
          chainId,
          address,
        ]
      ),
    ]
  );

export const getDigest = (
  domainSeparator: string,
  owner: string,
  spender: string,
  value: BigNumber,
  nonce: number,
  deadline: number
) =>
  ethers.utils.keccak256(
    ethers.utils.solidityPack(
      ['bytes1', 'bytes1', 'bytes32', 'bytes32'],
      [
        '0x19',
        '0x01',
        domainSeparator,
        ethers.utils.keccak256(
          ethers.utils.defaultAbiCoder.encode(
            ['bytes32', 'address', 'address', 'uint256', 'uint256', 'uint256'],
            [
              ethers.utils.keccak256(
                ethers.utils.toUtf8Bytes(
                  'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
                )
              ),
              owner,
              spender,
              value.toString(),
              nonce,
              deadline,
            ]
          )
        ),
      ]
    )
  );

export const getECSign = (privateKey: string, digest: string) =>
  ecsign(
    Buffer.from(digest.slice(2), 'hex'),
    Buffer.from(privateKey.replace('0x', ''), 'hex')
  );
