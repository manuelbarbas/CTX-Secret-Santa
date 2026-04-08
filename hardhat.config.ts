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
    // SKALE Base Sepolia Testnet
    skaleBaseSepolia: {
      url: process.env.SKALE_BASE_SEPOLIA_RPC_URL || 'https://base-sepolia-testnet.skalenodes.com/v1/jubilant-horrible-ancha',
      chainId: 324705682,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    // BITE V2 Sandbox 2 Testnet
    biteV2Sandbox2: {
      url: process.env.BITE_V2_SANDBOX2_RPC_URL || 'https://base-sepolia-testnet.skalenodes.com/v1/bite-v2-sandbox',
      chainId: 196243392,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    // Legacy network name (for backward compatibility)
    skale: {
      url: process.env.SKALE_BASE_SEPOLIA_RPC_URL || 'https://base-sepolia-testnet.skalenodes.com/v1/jubilant-horrible-ancha',
      chainId: 324705682,
      accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
    },
    hardhat: {
      chainId: 324705682,
    },
  },
  paths: {
    sources: './',
    tests: './test',
    cache: './cache',
    artifacts: './artifacts',
  },
};
