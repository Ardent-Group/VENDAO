import { ethers, run } from "hardhat";

async function main() {
  const _admin = "0xF15EDd201f8F8869F29adCB0476D8cc3562470bc";
  const spookyDEX = "0xF491e7B69E4244ad4002BC14e878a34207E38c29";
  const ftm_price_feed = "0xf4766552D15AE4d256Ad41B6cf2933482B0680dc";
  // Deploy vendao contract
  const Vendao = await ethers.getContractFactory("Vendao");
  const vendao = await Vendao.deploy();

  await vendao.deployed();

  console.log(`Vendao is deployed to ${vendao.address}`);
  
  // Deploy VenAccessControl contract
  const VenAccessControl = await ethers.getContractFactory("VenAccessControl");
  const venAccessControl = await VenAccessControl.deploy(vendao.address, _admin);

  await venAccessControl.deployed();

  console.log(`VenAccessControl is deployed to ${venAccessControl.address}`);
  
  // Deploy VenAccessTicket contract
  const VenAccessTicket = await ethers.getContractFactory("VenAccessTicket");
  const venAccessTicket = await VenAccessTicket.deploy(venAccessControl.address);

  await venAccessTicket.deployed();

  console.log(`VenAccessTicket is deployed to ${venAccessTicket.address}`);

  // Deploy VenVoting contract
  const VenVoting = await ethers.getContractFactory("VenVoting");
  const venVoting = await VenVoting.deploy(venAccessControl.address);

  await venVoting.deployed();

  console.log(`VenVoting is deployed to ${venVoting.address}`);

  // Initiate access control for VENDAO
  await vendao.init(venAccessTicket.address, venAccessControl.address, spookyDEX, ftm_price_feed);
  console.log(`VENDAO successfully initiated access control`);
  

  console.log(`Verifying VENDAO contract....`);
  await run("verify: verify", {
    address: vendao.address,
    constructorArguments: []
  });

  console.log(`Verifying VenAccessControl contract....`);
  await run("verify:verify", {
    address: venAccessControl.address,
    constructorArguments: [
      vendao.address,
      _admin
    ]
  });

  console.log(`Verifying VenAccessTicket contract....`);
  await run("verify:verify", {
    address: venAccessTicket.address,
    constructorArguments: [
      venAccessControl.address
    ]
  });

  console.log(`Verifying VenVoting contract....`);
  await run("verify:verify", {
    address: venVoting.address,
    constructorArguments: [
      venAccessControl.address
    ]
  });
  
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
