import { task } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';

task('accounts', 'Prints the list of accounts', async (_, hre) => {
  const accounts = await hre.ethers.getSigners();
  for (const account of accounts) {
    console.log(account.address);
  }
});

export default {
  solidity: {
    version: '0.8.28',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    skale: {
      url: process.env.SKALE_RPC_URL || 'https://base-sepolia-testnet.skalenodes.com/v1/miniature-live-tabit',
      chainId: 2090472038,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    hardhat: {
      chainId: 2090472038,
    },
  },
  paths: {
    sources: './',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
};
