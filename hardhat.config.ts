require("dotenv").config({path: ".env"});
import "hardhat-tracer";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";

const FANTOM_RPC_URL = process.env.FANTOM_RPC_URL;
const PRIVATE_KEYS = process.env.PRIVATE_KEY;
const API_KEY = process.env.API_KEY

module.exports = {
  solidity: "0.8.20",
  networks: {
    forking: {
      url: FANTOM_RPC_URL
    },
    fantom: {
      url: FANTOM_RPC_URL,
      accounts: [PRIVATE_KEYS]
    }
  },
  etherscan: {
    apikey: API_KEY
  }
}