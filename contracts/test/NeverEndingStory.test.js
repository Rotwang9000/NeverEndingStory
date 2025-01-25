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
        
        // Deploy mock VRF coordinator first
        const MockVRF = await ethers.getContractFactory("MockVRFCoordinator");
        mockVRF = await MockVRF.deploy();
        await mockVRF.deployed();

        // Deploy story contract with mock coordinator
        const Story = await ethers.getContractFactory("NeverEndingStory");
        story = await Story.deploy(SUBSCRIPTION_ID, mockVRF.address);
        await story.deployed();

        // Listen for debug events
        mockVRF.on("DebugFulfill", (requestId, consumer, words) => {
            console.log("Debug Fulfill:", {
                requestId: requestId.toString(),
                consumer,
                words: words.map(w => w.toString())
            });
        });
    });

    // Add missing test cases from MultiPromptStory.test.js
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
            const balanceBefore = await ethers.provider.getBalance(story.address);
            const potBefore = await story.pot();
            console.log("Before finalize:", {
                balance: ethers.utils.formatEther(balanceBefore),
                pot: ethers.utils.formatEther(potBefore)
            });

            story.on("FundsTracking", (action, amount, pot, balance) => {
                console.log("Funds:", action, {
                    amount: ethers.utils.formatEther(amount),
                    pot: ethers.utils.formatEther(pot),
                    balance: ethers.utils.formatEther(balance)
                });
            });

            await expect(story.finalizeRound())
                .to.emit(story, "RoundFinalized")
                .withArgs(1, 0, "Test prompt");

            const balanceAfter = await ethers.provider.getBalance(story.address);
            const potAfter = await story.pot();
            console.log("After finalize:", {
                balance: ethers.utils.formatEther(balanceAfter),
                pot: ethers.utils.formatEther(potAfter)
            });
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

    // Keep existing VRF Random Distribution tests
    describe("VRF Random Distribution", function () {
        beforeEach(async function () {
            const promptFee = ethers.utils.parseEther("0.1");
            const voteFee = ethers.utils.parseEther("0.2");
            
            // Verify initial state
            expect(await story.verifyPotBalance()).to.be.true;
            
            // Submit and complete 100 rounds with balance checking
            for(let i = 0; i < 100; i++) {
                const balanceBefore = await ethers.provider.getBalance(story.address);
                const potBefore = await story.pot();
                const actualBalance = await story.getActualBalance();
                
                console.log(`Round ${i}:`, {
                    balance: ethers.utils.formatEther(balanceBefore),
                    pot: ethers.utils.formatEther(potBefore),
                    actualBalance: ethers.utils.formatEther(actualBalance)
                });

                // Verify pot never exceeds balance
                expect(potBefore).to.be.lte(balanceBefore);
                
                await story.connect(addr1).submitPrompt(`Prompt ${i}`, { value: promptFee });
                await increaseTime(3 * HOURS);
                await story.advanceToVoting();
                await story.connect(addr2).voteOnPrompt(i, { value: voteFee });
                await increaseTime(3 * HOURS);
                
                // Verify balance after each round
                expect(await story.verifyPotBalance()).to.be.true;
                
                if (i < 99) {
                    await story.finalizeRound();
                }
            }
        });

        it("Should request random number after 100 winners", async function () {
            const initialPot = await story.pot();
            console.log("Initial pot:", initialPot.toString());
            expect(initialPot).to.be.gt(0);

            // Listen for debug events
            story.on("DebugTransfer", (action, to, amount, currentPot) => {
                console.log("Debug Transfer:", {
                    action,
                    to,
                    amount: amount.toString(),
                    currentPot: currentPot.toString()
                });
            });

            await story.finalizeRound();
            const filter = mockVRF.filters.RandomWordsRequested();
            const events = await mockVRF.queryFilter(filter);
            const requestId = events[events.length - 1].args.requestId;
            
            await mockVRF.fulfillRandomWords(requestId, story.address, {
                gasLimit: 15000000 // increase gas
            });

            // Wait for the next block to ensure all state changes are processed
            await ethers.provider.getBlock("latest");
            
            const finalPot = await story.pot();
            console.log("Final pot:", finalPot.toString());
            expect(finalPot).to.equal(0);
        });

        it("Should distribute pot after 100 rounds", async function () {
            const initialPot = await story.pot();
            const initialBalance = await ethers.provider.getBalance(story.address);
            console.log("Initial state:", {
                pot: ethers.utils.formatEther(initialPot),
                balance: ethers.utils.formatEther(initialBalance)
            });

            // Listen for all debug events
            story.on("DebugBalance", (msg, balance, pot) => {
                console.log("Debug Balance:", msg, {
                    balance: ethers.utils.formatEther(balance),
                    pot: ethers.utils.formatEther(pot)
                });
            });

            // Finalize round
            const tx = await story.finalizeRound();
            await tx.wait();

            // Process VRF request
            const filter = mockVRF.filters.RandomWordsRequested();
            const events = await mockVRF.queryFilter(filter);
            const requestId = events[events.length - 1].args.requestId;
            
            await mockVRF.fulfillRandomWords(requestId, story.address, {
                gasLimit: 15000000
            });

            // Verify final state
            const finalPot = await story.pot();
            const finalBalance = await ethers.provider.getBalance(story.address);
            console.log("Final state:", {
                pot: ethers.utils.formatEther(finalPot),
                balance: ethers.utils.formatEther(finalBalance)
            });

            expect(finalPot).to.equal(0);
            expect(finalBalance).to.equal(0);
        });
    });
});
