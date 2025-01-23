const { expect } = require("chai");
const { ethers } = require("hardhat");
const { increaseTime, HOURS, DAYS } = require("./helpers");

describe("NeverEndingStory", function () {
    let story;
    let mockVRF;
    let owner;
    let addr1;
    let addr2;
    const SUBSCRIPTION_ID = 1234;

    beforeEach(async function () {
        [owner, addr1, addr2] = await ethers.getSigners();
        
        // Deploy mock VRF coordinator
        const MockVRF = await ethers.getContractFactory("MockVRFCoordinator");
        mockVRF = await MockVRF.deploy();
        await mockVRF.deployed();

        // Deploy story contract
        const Story = await ethers.getContractFactory("NeverEndingStory");
        story = await Story.deploy(SUBSCRIPTION_ID);
        await story.deployed();
    });

    // ...existing test cases from MultiPromptStory.test.js...

    describe("VRF Random Distribution", function () {
        beforeEach(async function () {
            const promptFee = ethers.utils.parseEther("0.1");
            const voteFee = ethers.utils.parseEther("0.2");
            
            // Submit and complete 100 rounds
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

        it("Should request random number after 100 winners", async function () {
            const initialPot = await story.pot();
            expect(initialPot).to.be.gt(0);

            await story.finalizeRound();
            await mockVRF.fulfillRandomWords(1, story.address);

            expect(await story.pot()).to.equal(0);
        });

        it("Should distribute pot when idle", async function () {
            await increaseTime(DAYS + 1);
            
            await story.distributeIdlePot();
            await mockVRF.fulfillRandomWords(1, story.address);

            expect(await story.pot()).to.equal(0);
        });
    });
});
