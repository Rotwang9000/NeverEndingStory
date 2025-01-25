const { expect } = require("chai");
const { ethers } = require("hardhat");
const { increaseTime, HOURS } = require("./helpers");

describe("NeverEndingStory Reentrancy Tests", function () {
  let story, owner, attacker, ReentrantAttacker;

  beforeEach(async function () {
    [owner] = await ethers.getSigners();
    const MockVRF = await ethers.getContractFactory("MockVRFCoordinator");
    const mockVRF = await MockVRF.deploy();
    await mockVRF.deployed();

    const Story = await ethers.getContractFactory("NeverEndingStory");
    story = await Story.deploy(123, mockVRF.address);
    await story.deployed();

    ReentrantAttacker = await ethers.getContractFactory("ReentrantAttacker");
    attacker = await ReentrantAttacker.deploy(story.address);
    await attacker.deployed();

    await story.submitPrompt("Test Prompt", { value: ethers.utils.parseEther("0.1") });
    await increaseTime(3 * HOURS);
    await story.advanceToVoting();
  });

  it("Should prevent reentrancy on submitPrompt", async function () {
    await expect(
      attacker.attackSubmitPrompt({ value: ethers.utils.parseEther("0.1") })
    ).to.be.reverted;
  });

  it("Should prevent reentrancy on voteOnPrompt", async function () {
    // Make attacker the owner to receive dev fees
    await story.transferOwnership(attacker.address);
    
    // Fund attacker with more ETH to ensure sufficient gas for reentry attempt
    await owner.sendTransaction({
      to: attacker.address,
      value: ethers.utils.parseEther("5.0")
    });

    // Try to perform the reentrancy attack
    await expect(
      attacker.attackVoteOnPrompt(0, { 
        value: ethers.utils.parseEther("1.0"),
        gasLimit: 500000 
      })
    ).to.be.revertedWith("ReentrancyGuard: reentrant call");
  });

  it("Should prevent reentrancy during finalization", async function () {
    // Submit an attacker prompt in submission phase
    await increaseTime(3 * HOURS); // ensure submission phase has ended for round 1
    await story.finalizeRound();   // finalize existing round so we start a new one

    // New round is now in SUBMISSION phase
    await story.submitPrompt("Attacker prompt", { value: ethers.utils.parseEther("0.1") });
    await increaseTime(3 * HOURS);
    await story.advanceToVoting();

    // Make attacker the top voter on that prompt
    await attacker.attackVoteOnPrompt(0, { value: ethers.utils.parseEther("2.0") });
    await increaseTime(3 * HOURS);

    // Now finalization pays the attacker, triggering fallback
    await expect(attacker.attackFinalizeRound()).to.be.revertedWith("ReentrancyGuard: reentrant call");
  });

  it("Should prevent reentrancy during pot distribution", async function () {
    // Finish current round
    await increaseTime(3 * HOURS);
    await story.finalizeRound();

    // New round in SUBMISSION phase
    await story.submitPrompt("Attacker prompt", { value: ethers.utils.parseEther("0.1") });
    await increaseTime(3 * HOURS);
    await story.advanceToVoting();

    await story.voteOnPrompt(0, { value: ethers.utils.parseEther("0.5") });
    await increaseTime(3 * HOURS);
    await story.finalizeRound();

    // Wait 1 day idle
    await increaseTime(24 * 3600);
    // Attack pot distribution
    await expect(attacker.attackDistributeIdlePot()).to.be.revertedWith("ReentrancyGuard: reentrant call");
  });

  it("Should prevent reentrancy via receive function", async function () {
    // Add a dev-fee-triggering transaction so fallback can reenter
    // Make attacker the owner so dev fees go to them
    await story.transferOwnership(attacker.address);
    await owner.sendTransaction({
      to: attacker.address,
      value: ethers.utils.parseEther("1.0")
    });

    // This triggers dev fee payment to attacker, which calls fallback
    await expect(
      attacker.attackReceive({ value: ethers.utils.parseEther("0.1") })
    ).to.be.revertedWith("ReentrancyGuard: reentrant call");
  });
});