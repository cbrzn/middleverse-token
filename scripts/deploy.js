const hre = require('hardhat');

async function main () {
  const MVGToken = await hre.ethers.getContractFactory('MiddleverseGold');
  const mvgtoken = await MVGToken.deploy();

  await mvgtoken.deployed();

  console.log('MVGToken deployed to:', mvgtoken.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
