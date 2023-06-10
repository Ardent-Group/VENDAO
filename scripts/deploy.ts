import { ethers } from "hardhat";

async function main() {
  const admin = "0x5DE9d9C1dC9b407a9873E2F428c54b74c325b82b";
  // Deploy vendao contract
  const Vendao = await ethers.getContractFactory("Vendao");
  const vendao = await Vendao.deploy();

  await vendao.deployed();

  console.log(`Vendao is deployed to ${vendao.address}`);
  
  // Deploy VenAccessControl contract
  const VenAccessControl = await ethers.getContractFactory("VenAccessControl");
  const venAccessControl = await VenAccessControl.deploy(vendao.address, admin);

  await venAccessControl.deployed();

  console.log(`VenAccessControl is deployed to ${venAccessControl.address}`);
  
  // Deploy VenAccessTicket contract
  const VenAccessTicket = await ethers.getContractFactory("VenAccessTicket");
  const venAccessTicket = await VenAccessControl.deploy()
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
