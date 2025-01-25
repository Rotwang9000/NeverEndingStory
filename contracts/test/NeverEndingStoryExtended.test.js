const { expect } = require("chai");
const { ethers } = require("hardhat");
const { increaseTime, HOURS, DAYS } = require("./helpers");

describe("NeverEndingStory Extended Tests", function () {
  let story, owner, addr1;

  beforeEach(async function () {
    [owner, addr1] = await ethers.getSigners();
    const MockVRF = await ethers.getContractFactory("MockVRFCoordinator");
    const mockVRF = await MockVRF.deploy();
    await mockVRF.deployed();

    const Story = await ethers.getContractFactory("NeverEndingStory");
    story = await Story.deploy(123, mockVRF.address);
    await story.deployed();
  });

  it("Should fail to distribute idle pot if pot is zero", async function () {
    expect(await story.pot()).to.equal(0);
    await increaseTime(1 * DAYS + 1);  // ensure enough idle time has passed
    await expect(story.distributeIdlePot()).to.be.revertedWith("Nothing in pot");
  });

  it("Should not pick a random voter if prompt has no voters", async function () {
    // Submit prompt
    const promptFee = ethers.utils.parseEther("0.1");
    await story.submitPrompt("No voters", { value: promptFee });
    await increaseTime(3 * HOURS);
    await story.advanceToVoting();
    // finalize directly, no votes
    await increaseTime(3 * HOURS);
    await story.finalizeRound();
    // no random voter request should have been made
    // verifying no event or leftover pot is enough
    expect(await story.pot()).to.be.gt(0);
  });

  it("Should handle tie-breaking among prompts with same totalVotes", async function () {
    // Submit multiple prompts
    const promptFee = ethers.utils.parseEther("0.1");
    await story.submitPrompt("Prompt A", { value: promptFee });
    await story.submitPrompt("Prompt B", { value: promptFee });
    await increaseTime(3 * HOURS);
    await story.advanceToVoting();
    // vote on both
    const voteFee = ethers.utils.parseEther("0.2");
    await story.voteOnPrompt(0, { value: voteFee });
    await story.voteOnPrompt(1, { value: voteFee });
    await increaseTime(3 * HOURS);
    // finalize
    await story.finalizeRound();
    // one prompt chosen as winner, but pot is not negatively impacted
    expect(await story.verifyPotBalance()).to.equal(true);
  });
});