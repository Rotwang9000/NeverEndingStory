const { expect } = require("chai");
const { ethers } = require("hardhat");
const { increaseTime, HOURS, DAYS } = require("./helpers");

describe("MultiPromptStory", function () {
    let story;
    let mockVRF;
    let owner;
    let addr1;
    let addr2;
    const SUBSCRIPTION_ID = 1234;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        
        // Deploy mock VRF coordinator first
        const MockVRF = await ethers.getContractFactory("MockVRFCoordinator");
        mockVRF = await MockVRF.deploy();
        await mockVRF.deployed();

        // Deploy story contract with VRF subscription
        const Story = await ethers.getContractFactory("MultiPromptStory");
        story = await Story.deploy(SUBSCRIPTION_ID);
        await story.deployed();
    });

    describe("Prompt Submission", function () {
        it("Should allow submitting a prompt with payment", async function () {
            const promptFee = ethers.utils.parseEther("0.1");
            await expect(story.connect(addr1).submitPrompt("Test prompt", { value: promptFee }))
                .to.emit(story, "PromptSubmitted")
                .withArgs(1, 0, addr1.address, "Test prompt");
        });

        it("Should not allow submission after time ends", async function () {
            await increaseTime(4 * HOURS);
            const promptFee = ethers.utils.parseEther("0.1");
            await expect(
                story.connect(addr1).submitPrompt("Test prompt", { value: promptFee })
            ).to.be.revertedWith("Submission time ended");
        });
    });

    describe("Voting", function () {
        beforeEach(async function () {
            const promptFee = ethers.utils.parseEther("0.1");
            await story.connect(addr1).submitPrompt("Test prompt", { value: promptFee });
            await increaseTime(3 * HOURS);
            await story.advanceToVoting();
        });

        it("Should allow voting on prompts", async function () {
            const voteFee = ethers.utils.parseEther("0.2");
            await expect(story.connect(addr2).voteOnPrompt(0, { value: voteFee }))
                .to.emit(story, "VoteCast")
                .withArgs(1, 0, addr2.address, voteFee);
        });
    });

    describe("Round Finalization", function () {
        beforeEach(async function () {
            const promptFee = ethers.utils.parseEther("0.1");
            await story.connect(addr1).submitPrompt("Test prompt", { value: promptFee });
            await increaseTime(3 * HOURS);
            await story.advanceToVoting();
            const voteFee = ethers.utils.parseEther("0.2");
            await story.connect(addr2).voteOnPrompt(0, { value: voteFee });
            await increaseTime(3 * HOURS);
        });

        it("Should finalize round correctly", async function () {
            await expect(story.finalizeRound())
                .to.emit(story, "RoundFinalized")
                .withArgs(1, 0, "Test prompt");
        });
    });

    describe("Shout Outs", function () {
        it("Should allow posting shout outs with fee", async function () {
            const shoutFee = ethers.utils.parseEther("0.01");
            await expect(story.connect(addr1).postShoutOut("Hello!", { value: shoutFee }))
                .to.emit(story, "ShoutOut")
                .withArgs(addr1.address, "Hello!", shoutFee);
        });
    });

    describe("VRF Random Distribution", function () {
        beforeEach(async function () {
            // Submit and complete 100 rounds to trigger pot distribution
            const promptFee = ethers.utils.parseEther("0.1");
            const voteFee = ethers.utils.parseEther("0.2");
            
            for(let i = 0; i < 100; i++) {
                await story.connect(addr1).submitPrompt(`Prompt ${i}`, { value: promptFee });
                await increaseTime(3 * HOURS);
                await story.advanceToVoting();
                await story.connect(addr2).voteOnPrompt(i, { value: voteFee });
                await increaseTime(3 * HOURS);
                if (i < 99) {
                    await story.finalizeRound();
                }
            }
        });

        it("Should request random number on 100th winner", async function () {
            const initialPot = await story.pot();
            expect(initialPot).to.be.gt(0);

            // Finalize 100th round
            await story.finalizeRound();

            // Simulate VRF callback
            await mockVRF.fulfillRandomWords(1, story.address);

            // Check pot was distributed
            const finalPot = await story.pot();
            expect(finalPot).to.equal(0);
        });

        it("Should distribute pot on idle timeout", async function () {
            await increaseTime(DAYS + 1);
            
            await story.distributeIdlePot();
            await mockVRF.fulfillRandomWords(1, story.address);

            const finalPot = await story.pot();
            expect(finalPot).to.equal(0);
        });

        it("Should track VRF requests correctly", async function () {
            await story.finalizeRound();
            expect(await story.pendingRandomDistribution(1)).to.be.true;
            
            await mockVRF.fulfillRandomWords(1, story.address);
            expect(await story.pendingRandomDistribution(1)).to.be.false;
        });
    });
});
