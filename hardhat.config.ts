require("dotenv").config({path: ".env"});
import "hardhat-tracer";
import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-verify";
import "hardhat-contract-sizer";

const FANTOM_RPC_URL = process.env.FANTOM_RPC_URL;
const PRIVATE_KEYS = process.env.PRIVATE_KEY;
const API_KEY = process.env.API_KEY
const FANTOM_MAINNET_URL = process.env.FANTOM_MAINNET_URL;



module.exports = {
  solidity: "0.8.18",
  networks: {
    forking: {
      url: FANTOM_RPC_URL
    },
    fantom_testnet: {
      url: FANTOM_RPC_URL,
      accounts: [PRIVATE_KEYS]
    },
    fantom: {
      url: FANTOM_MAINNET_URL,
      accounts: [PRIVATE_KEYS]
    }
  },
  etherscan: {
    apikey: API_KEY
  }
}