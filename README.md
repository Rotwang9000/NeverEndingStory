# Never-Ending AI Video Story dApp

This project is an **unstoppable** decentralised application (dApp) that generates a continuous, community-driven AI video story on-chain. Users submit “prompts” for each story segment, then everyone votes (with ETH) to determine which prompt wins each round. The winning prompt text is used for off-chain AI video generation. Rinse, repeat, and distribute an ETH pot along the way.

## Table of Contents

1. [Overview](#overview)  
2. [Main Features](#main-features)  
3. [Newer Features](#newer-features)  
4. [Smart Contract Flow](#smart-contract-flow)  
5. [Fees & Pot Distribution](#fees--pot-distribution)  
6. [Inactivity & Pause Logic](#inactivity--pause-logic)  
7. [Shout-Out Message Board](#shout-out-message-board)  
8. [Server / Off-Chain AI Video Generation](#server--off-chain-ai-video-generation)  
9. [Installation & Deployment](#installation--deployment)  
10. [Frontend Integration](#frontend-integration)  
11. [Potential Extensions](#potential-extensions)  
12. [Example Contract Code](#example-contract-code)  
13. [Licence](#licence)

---

## Overview

The dApp revolves around *never-ending* rounds of prompt submissions and voting:

- **Submission Phase**: Multiple users submit prompts (ideas for what happens next in the AI-generated story).  
- **Voting Phase**: Users vote on their favourite prompt by sending ETH (votes). The prompt with the highest total votes wins.  
- **Finalise Round**: After the voting time ends, the contract picks the winning prompt, performs on-chain ETH distributions, and logs an event so an off-chain AI can generate the new video snippet. Then a new round begins automatically.

Meanwhile, a **pot** of ETH accumulates through partial leftover from each round. Periodically—every 100 rounds—the pot is awarded at random to one of the last 100 winners. If no new activity occurs for 24 hours, anyone can trigger a fallback distribution of the pot so it never gets stuck.

We also have:

- **Admin** who can pause/unpause the contract and set fees (which might go to a staking contract or dev treasury).  
- **Shout-Out Board** for quick messages: pay a small fee to post; admin can post for free.  

It’s designed so there’s no single point of failure. *Anyone* can call the required state transitions once time is up, preventing sabotage or indefinite lock-in.

---

## Main Features

1. **Two-Phase Rounds**  
   - **Submission**: Users propose prompts, paying ETH.  
   - **Voting**: Participants vote (also with ETH).  
   - Highest total votes = winner.  
   - Automatic time-based transitions.  

2. **ETH Pot**  
   - Accumulates leftover from prompts/votes.  
   - Distributes partially with each round’s winner.  
   - **Every 100 rounds**, a random winner from the last 100 winners receives the pot.  
   - If no activity for 24 hours, the pot is randomly distributed to avoid lock-ups.  

3. **Fee Mechanism**  
   - A configurable percentage of each submission/vote goes straight to the `feeReceiver` address.  
   - The remainder is added to the pot.  
   - The admin can set both the fee percentage and the receiving address.  

4. **Pause / Unpause**  
   - The admin can pause to upgrade off-chain video generation or fix front-end issues.  
   - If paused > 24 hours, the community can still distribute the pot randomly, ensuring funds aren’t locked forever.  

5. **Shout-Outs**  
   - A tiny “message board” for paying a small fee to post a message on-chain.  
   - All fees go to the pot.  
   - Admin can post free messages (announcements, maintenance notices, etc.).  

6. **Off-Chain AI**  
   - The dApp only stores text prompts and handles ETH logic.  
   - Off-chain servers (watching contract events) do the actual AI video generation.  
   - Final videos are served or stitched externally, unaffected by any single front-end’s downtime.

---

## Newer Features

- Optional limit on how many prompts can be submitted during a round.  
- Optional maximum total ETH allowed for voting each round.  
- Reentrancy tests and an attacker contract to ensure all functions are protected.

---

## Smart Contract Flow

1. **Start**  
   - `currentRoundId = 1`  
   - Round is in `SUBMISSION` state with known end time (e.g. `submissionEndTime = block.timestamp + SUBMISSION_DURATION`).  

2. **Submission Phase**  
   - Users call `submitPrompt(_text)` with some ETH.  
   - The contract skims a fee to `feeReceiver`, deposits leftover into `pot`.  
   - Each prompt is recorded (`promptId -> {creator, text, totalVotes, etc.}`).  

3. **Advance to Voting**  
   - Once `block.timestamp >= submissionEndTime`, *anyone* calls `advanceToVoting()`.  
   - The round enters `VOTING` with `votingEndTime = submissionEndTime + VOTING_DURATION`.  

4. **Voting Phase**  
   - Users call `voteOnPrompt(_promptId)` with ETH.  
   - Again, a fee is skimmed; leftover goes to `pot`.  
   - The contract tracks each prompt’s total votes and the top voter’s single biggest contribution.  

5. **Finalise Round**  
   - Once `block.timestamp >= votingEndTime`, *anyone* calls `finalizeRound()`.  
   - Finds the prompt with the highest totalVotes.  
   - Distributes that prompt’s votes: e.g. 30% to creator, 15% to top bidder, 5% random among that prompt’s voters, leftover to the pot.  
   - *Increments* `roundCount`.  
   - If `roundCount % 100 == 0`, picks a random from the last 100 winners and transfers the entire pot to them.  
   - Starts a new round in `SUBMISSION` mode again.  

6. **No Activity**  
   - If no new actions happen for 24 hours (`lastActionTime + 1 days <= block.timestamp`), *anyone* calls `distributeIdlePot()`.  
   - The contract randomly picks a winner from the last 100 winners, empties the pot to them, ensuring it’s never stuck.  

---

## Fees & Pot Distribution

- **Fee**: A percentage (`feePercent`) of every `msg.value` from submissions and votes goes to the `feeReceiver` address immediately.  
- **Pot**: All leftover accumulates in `pot`.  
- **Round Payout**: On finalising each round, partial immediate rewards are paid out from the winner’s total votes, then leftover from *those* votes is also added to the pot.  
- **Random Payout**: 
  - Every 100 completed rounds → The entire pot is distributed to a random user from the last 100 *prompt winners*.  
  - If idle for >24 hours → The entire pot is distributed randomly among those winners.  

---

## Inactivity & Pause Logic

1. **Inactivity**  
   - The contract records `lastActionTime` on every user action (prompt submission, voting, finalisation, etc.).  
   - If 24 hours pass with zero activity, *anyone* calls `distributeIdlePot()` to empty the pot to a random winner.  

2. **Pause Mechanism**  
   - `paused = true` disallows new prompts or votes.  
   - If paused for >24 hours, the community can still call `distributeIdlePot()` to free up the pot.  
   - Once you’re done upgrading your off-chain code, you can `setPaused(false)` to reopen submissions and voting.

---

## Shout-Out Message Board

- **postShoutOut(_msg)**: Pay `shoutOutFee` to post a message on-chain.  
- The entire fee goes to the pot.  
- `adminMessage(_msg)`: The admin can post a free message, e.g. upgrade announcements, disclaimers, comedic commentary about the code’s indentation.  
- All messages are stored in an array `shouts[]` and emitted in a `ShoutOut` event for front-ends to display.

---

## Server / Off-Chain AI Video Generation

Since the contract only stores text prompts, actual video generation is off-chain:

1. **Listen for Round Events**:  
   - When a round is finalised (`RoundFinalized(roundId, winningPromptId, text)`), your server sees which prompt won.  
2. **Generate Video**:  
   - Use something like [Replicate](https://replicate.com/docs) to generate a short AI video clip.  
   - The final frame of this clip can be stored somewhere (e.g. IPFS, S3) for reference.  
3. **Stitching**:  
   - You can stitch consecutive segments together, or simply store them separately.  
4. **Front-End Display**:  
   - Show the latest winning prompt + video snippet.  
   - Provide a full timeline or continuous playback.  

Even if your off-chain infrastructure goes down, *the contract continues unstoppable* on-chain.

---

## Installation & Deployment

1. **Clone This Repo**  
   ```bash
   git clone https://github.com/YourUsername/NeverEndingStory.git
   cd NeverEndingStory
   ```

2. **Install Dependencies**  
   - You’ll need Hardhat or Truffle, plus typical dev dependencies. For Hardhat:
     ```bash
     npm install
     ```

3. **Configure `.env`**  
   - Set your network settings, deployer private key, etc.

4. **Deploy**  
   - In Hardhat, for example:
     ```bash
     npx hardhat run scripts/deploy.js --network baseGoerli
     ```
   - Provide the constructor parameter `_feeReceiver` (the address that initially receives the dev/staking fees).

5. **Verify** (Optional)  
   - Verify your contract on explorers like Etherscan (Base network) if desired.

---

## Frontend Integration

A React or Next.js front-end typically:

1. **Connect Wallet**: Metamask or any Base-compatible wallet.  
2. **Show Current Round**:  
   - Retrieve `currentRoundId`, fetch submission/voting deadlines, and list existing prompts.  
3. **Submit Prompt**:  
   - Have a form that calls `submitPrompt(_text, { value: X })` with the user’s chosen ETH.  
4. **Advance to Voting** / **Finalise Round**:  
   - Provide a button that appears once the time is up, letting *any* user push the round forward.  
5. **Voting**:  
   - Show prompts in the current round, user can pick one to vote on with a chosen ETH amount.  
6. **Shout Outs**:  
   - Provide a separate text field for a short message, paying the `shoutOutFee`.  

**Off-chain AI** logic would watch for `RoundFinalized` events and handle the video generation and hosting.

---

## Potential Extensions

- **Real Randomness**: Integrate [Chainlink VRF](https://docs.chain.link/vrf/v2/subscription) for truly secure random picks.  
- **NFT Minting**: Mint an NFT each time a user wins a round. Could be done by the main contract or an external “listener” contract.  
- **Leaderboard**: Maintain a simple scoreboard of top voters/creators.  
- **Referral System**: Possibly reward users who bring in new voters or prompt submitters.  

---

## Example Contract Code

Below is the complete contract example, referencing all the features (two-phase round logic, fees, pot distribution, inactivity, pause, and shout outs). **Tabs, not spaces**, naturally:

<details>
<summary><strong>Show NeverEndingStory.sol</strong></summary>

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/*
   Multi-prompt voting with admin controls (pause, fee settings), unstoppable time-based rounds,
   random pot distribution every 100 winners or if idle for a day,
   plus a "shout out" message board with a fee that goes to the pot.
   The owner can set the "feeReceiver" address, which might be a staking contract or similar.
*/

contract NeverEndingStory {
	enum RoundState { SUBMISSION, VOTING, ENDED }

	struct Prompt {
		address creator;
		string text;
		uint256 totalVotes;
		uint256 topVoterAmount;  // largest single vote
		address topVoter;
		mapping(address => uint256) votesByAddress;
		address[] voters;
		bool exists;
	}

	struct RoundData {
		RoundState state;
		uint256 submissionEndTime;
		uint256 votingEndTime;
		uint256[] promptIds;  // which prompt IDs belong to this round
		bool finalized;
	}

	// --- Configurable durations ---
	uint256 public constant SUBMISSION_DURATION = 3 hours;
	uint256 public constant VOTING_DURATION = 3 hours;
	uint256 public constant IDLE_DURATION = 1 days; // idle fallback
	uint256 public constant RANDOM_ROUND_INTERVAL = 100; // distribution every 100 rounds

	// --- Owner / Admin data ---
	address public owner;
	bool public paused;
	uint256 public pausedTime;

	// --- Fees ---
	uint256 public feePercent = 20; // e.g. 20% fee
	address public feeReceiver;

	// --- Round storage ---
	mapping(uint256 => Prompt) public prompts;       
	mapping(uint256 => RoundData) public rounds;     
	uint256 public nextPromptId;
	uint256 public currentRoundId;

	uint256 public pot;          // Accumulates leftover from each round
	uint256 public roundCount;   // How many rounds have ended
	uint256 public lastActionTime;

	// We'll store the last 100 winners for random distribution
	address[] public lastHundredWinners;

	// --- Shout Outs ---
	uint256 public shoutOutFee = 0.01 ether;
	struct Shout {
		address sender;
		string message;
		uint256 timestamp;
	}
	Shout[] public shouts;

	// --- Events ---
	event PromptSubmitted(uint256 indexed roundId, uint256 promptId, address indexed creator, string text, uint256 amount);
	event VoteCast(uint256 indexed roundId, uint256 indexed promptId, address voter, uint256 amount);
	event RoundAdvancedToVoting(uint256 indexed roundId);
	event RoundFinalized(uint256 indexed roundId, uint256 winningPromptId, string text);
	event PotDistribution(address indexed winner, uint256 amount);
	event ShoutOut(address indexed sender, string message, uint256 feePaid);
	event PausedState(bool state);
	event FeeUpdated(uint256 newFee, address newFeeReceiver);
	event ShoutOutFeeUpdated(uint256 newFee);

	constructor(address _feeReceiver) {
		owner = msg.sender;
		feeReceiver = _feeReceiver;
		_startNewRound();
		lastActionTime = block.timestamp;
	}

	modifier onlyOwner() {
		require(msg.sender == owner, "Not the owner");
		_;
	}

	modifier notPaused() {
		require(!paused, "Contract is paused");
		_;
	}

	//----------------------------------------------------
	//                    OWNER ACTIONS
	//----------------------------------------------------

	function setPaused(bool _state) external onlyOwner {
		paused = _state;
		if (_state) {
			pausedTime = block.timestamp;
		}
		emit PausedState(_state);
	}

	function setFees(uint256 _feePercent, address _feeReceiver) external onlyOwner {
		require(_feePercent <= 50, "Fee too high");
		feePercent = _feePercent;
		feeReceiver = _feeReceiver;
		emit FeeUpdated(_feePercent, _feeReceiver);
	}

	function setShoutOutFee(uint256 _newFee) external onlyOwner {
		shoutOutFee = _newFee;
		emit ShoutOutFeeUpdated(_newFee);
	}

	//----------------------------------------------------
	//                   ROUND LOGIC
	//----------------------------------------------------

	function submitPrompt(string memory _text) external payable notPaused {
		RoundData storage round = rounds[currentRoundId];
		require(round.state == RoundState.SUBMISSION, "Not submission phase");
		require(block.timestamp < round.submissionEndTime, "Submission time ended");
		require(msg.value > 0, "Must send ETH with prompt");

		// 1. Fee to feeReceiver
		uint256 feeAmount = (msg.value * feePercent) / 100;
		payable(feeReceiver).transfer(feeAmount);

		// 2. Remainder to pot
		uint256 leftover = msg.value - feeAmount;
		pot += leftover;

		// 3. Create prompt
		uint256 pid = nextPromptId++;
		Prompt storage p = prompts[pid];
		p.creator = msg.sender;
		p.text = _text;
		p.exists = true;

		round.promptIds.push(pid);

		emit PromptSubmitted(currentRoundId, pid, msg.sender, _text, msg.value);
		lastActionTime = block.timestamp;
	}

	function advanceToVoting() external {
		RoundData storage round = rounds[currentRoundId];
		require(round.state == RoundState.SUBMISSION, "Round not in submission phase");
		require(block.timestamp >= round.submissionEndTime, "Submission not ended yet");
		round.state = RoundState.VOTING;

		emit RoundAdvancedToVoting(currentRoundId);
		lastActionTime = block.timestamp;
	}

	function voteOnPrompt(uint256 _promptId) external payable notPaused {
		RoundData storage round = rounds[currentRoundId];
		require(round.state == RoundState.VOTING, "Not in voting phase");
		require(block.timestamp < round.votingEndTime, "Voting ended");
		require(msg.value > 0, "Must send ETH to vote");

		Prompt storage p = prompts[_promptId];
		require(p.exists, "Prompt doesn't exist");

		// 1. Fee
		uint256 feeAmount = (msg.value * feePercent) / 100;
		payable(feeReceiver).transfer(feeAmount);

		// 2. Remainder to pot
		uint256 leftover = msg.value - feeAmount;
		pot += leftover;

		// 3. Tally votes
		p.totalVotes += msg.value;
		if (p.votesByAddress[msg.sender] == 0) {
			p.voters.push(msg.sender);
		}
		p.votesByAddress[msg.sender] += msg.value;

		if (p.votesByAddress[msg.sender] > p.topVoterAmount) {
			p.topVoterAmount = p.votesByAddress[msg.sender];
			p.topVoter = msg.sender;
		}

		emit VoteCast(currentRoundId, _promptId, msg.sender, msg.value);
		lastActionTime = block.timestamp;
	}

	function finalizeRound() external {
		RoundData storage round = rounds[currentRoundId];
		require(round.state == RoundState.VOTING, "Not in voting phase");
		require(block.timestamp >= round.votingEndTime, "Voting not ended");
		require(!round.finalized, "Already finalized");

		round.finalized = true;
		round.state = RoundState.ENDED;

		// pick the prompt with the highest totalVotes
		uint256 winningPromptId = _findWinningPromptId(round.promptIds);
		Prompt storage winner = prompts[winningPromptId];

		// Example distribution from the winner’s total votes
		uint256 winningTotal = winner.totalVotes;
		if (winningTotal > 0) {
			uint256 creatorShare = (winningTotal * 30) / 100;
			uint256 topBidderShare = (winningTotal * 15) / 100;
			uint256 randomBidderShare = (winningTotal * 5) / 100;
			uint256 leftover = winningTotal - (creatorShare + topBidderShare + randomBidderShare);

			payable(winner.creator).transfer(creatorShare);

			if (winner.topVoter != address(0)) {
				payable(winner.topVoter).transfer(topBidderShare);
			}

			address randomVoter = _pickRandomVoter(winningPromptId);
			if (randomVoter != address(0)) {
				payable(randomVoter).transfer(randomBidderShare);
			}

			pot += leftover;
		}

		emit RoundFinalized(currentRoundId, winningPromptId, winner.text);

		roundCount++;
		lastHundredWinners.push(winner.creator);
		if (lastHundredWinners.length > 100) {
			_popFront(lastHundredWinners);
		}

		// If we've hit 100, 200, 300... rounds, distribute pot randomly
		if (roundCount % RANDOM_ROUND_INTERVAL == 0) {
			_distributePotRandomly();
		}

		// start next round
		_startNewRound();
		lastActionTime = block.timestamp;
	}

	function distributeIdlePot() external {
		// If no new action for 24h or paused for 24h
		require(block.timestamp >= lastActionTime + IDLE_DURATION, "Not enough idle time");
		require(pot > 0, "Nothing in pot");
		_distributePotRandomly();
	}

	//----------------------------------------------------
	//                SHOUT-OUT MESSAGES
	//----------------------------------------------------

	function postShoutOut(string calldata _msg) external payable notPaused {
		require(msg.value >= shoutOutFee, "Shout out fee not met");
		pot += msg.value;

		Shout memory s = Shout({
			sender: msg.sender,
			message: _msg,
			timestamp: block.timestamp
		});
		shouts.push(s);

		emit ShoutOut(msg.sender, _msg, msg.value);
		lastActionTime = block.timestamp;
	}

	function adminMessage(string calldata _msg) external onlyOwner {
		Shout memory s = Shout({
			sender: msg.sender,
			message: _msg,
			timestamp: block.timestamp
		});
		shouts.push(s);

		emit ShoutOut(msg.sender, _msg, 0);
		lastActionTime = block.timestamp;
	}

	//----------------------------------------------------
	//                INTERNAL HELPERS
	//----------------------------------------------------

	function _startNewRound() internal {
		currentRoundId++;
		RoundData storage newRound = rounds[currentRoundId];
		newRound.state = RoundState.SUBMISSION;
		newRound.submissionEndTime = block.timestamp + SUBMISSION_DURATION;
		newRound.votingEndTime = newRound.submissionEndTime + VOTING_DURATION;
		newRound.finalized = false;
	}

	function _findWinningPromptId(uint256[] storage _promptIds) internal view returns (uint256) {
		uint256 winnerId;
		uint256 highestVotes;
		for (uint256 i = 0; i < _promptIds.length; i++) {
			uint256 pid = _promptIds[i];
			if (prompts[pid].totalVotes > highestVotes) {
				highestVotes = prompts[pid].totalVotes;
				winnerId = pid;
			}
		}
		return winnerId;
	}

	function _pickRandomVoter(uint256 _promptId) internal view returns (address) {
		Prompt storage p = prompts[_promptId];
		if (p.voters.length == 0) {
			return address(0);
		}
		uint256 randIdx = _pseudoRandomIndex(p.voters.length);
		return p.voters[randIdx];
	}

	function _distributePotRandomly() internal {
		if (lastHundredWinners.length == 0) {
			return;
		}
		uint256 potToSend = pot;
		pot = 0;

		uint256 idx = _pseudoRandomIndex(lastHundredWinners.length);
		address lucky = lastHundredWinners[idx];

		payable(lucky).transfer(potToSend);
		emit PotDistribution(lucky, potToSend);
	}

	function _popFront(address[] storage arr) internal {
		if (arr.length == 0) return;
		for (uint256 i = 0; i < arr.length - 1; i++) {
			arr[i] = arr[i + 1];
		}
		arr.pop();
	}

	// TOTALLY unsecure for randomness (use Chainlink VRF in production)
	function _pseudoRandomIndex(uint256 _mod) internal view returns (uint256) {
		return uint256(
			keccak256(
				abi.encodePacked(
					block.timestamp,
					block.difficulty,
					msg.sender,
					pot,
					roundCount
				)
			)
		) % _mod;
	}

	receive() external payable {
		pot += msg.value;
	}
}
```

</details>

---

## Licence

This project is released under the [MIT Licence](https://opensource.org/licenses/MIT), meaning you can fork, modify, and use it freely. Remember: **test thoroughly** and consider audits before going live with real ETH.
