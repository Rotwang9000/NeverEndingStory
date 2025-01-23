const { time } = require("@nomicfoundation/hardhat-network-helpers");

async function increaseTime(seconds) {
  await time.increase(seconds);
}

async function getLatestBlockTimestamp() {
  const latestBlock = await ethers.provider.getBlock("latest");
  return latestBlock.timestamp;
}

module.exports = {
  increaseTime,
  getLatestBlockTimestamp,
  HOURS: 3600,
  DAYS: 86400
};
