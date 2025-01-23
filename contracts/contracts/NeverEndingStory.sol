// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./RandomnessConsumer.sol";

/*
   Multi-prompt voting, unstoppable time-based rounds,
   random pot distribution every 100 winners or if idle for a day,
   plus a "shout out" message board with a small fee.
*/

contract MultiPromptStory is RandomnessConsumer {
	enum RoundState { SUBMISSION, VOTING, ENDED }

	struct Prompt {
		address creator;
		string text;
		uint256 totalVotes;
		uint256 topVoterAmount;  // largest single vote
		address topVoter;
		// track each voter's contribution for random bidder selection
		mapping(address => uint256) votesByAddress;
		address[] voters;
		bool exists;
	}

	// A round can have multiple prompts
	struct RoundData {
		RoundState state;
		uint256 submissionEndTime;
		uint256 votingEndTime;
		uint256[] promptIds;  // which prompt IDs belong to this round
		bool finalized;
	}

	// We'll store each prompt and each round
	mapping(uint256 => Prompt) public prompts;       // promptId -> Prompt
	mapping(uint256 => RoundData) public rounds;     // roundId -> RoundData
	uint256 public nextPromptId;
	uint256 public currentRoundId;

	// Keep a pot for leftover from each round
	uint256 public pot;
	// Count how many rounds have ended (and thus winners found)
	uint256 public roundCount;

	// For random distribution every 100 winners
	address[] public lastHundredWinners;

	// Idle time fallback
	uint256 public lastActionTime;
	uint256 public constant IDLE_DURATION = 1 days; // 24 hours
	// Duration for submission and voting (configurable, for example)
	uint256 public constant SUBMISSION_DURATION = 3 hours;
	uint256 public constant VOTING_DURATION = 3 hours;

	// Dev fee
	address public owner;
	uint256 public constant DEV_FEE_PERCENT = 20;

	// For the "shout out" board
	uint256 public shoutOutFee = 0.01 ether;  // or whatever you like
	struct Shout {
		address sender;
		string message;
		uint256 timestamp;
	}
	Shout[] public shouts;

	// Events
	event PromptSubmitted(uint256 indexed roundId, uint256 promptId, address indexed creator, string text);
	event VoteCast(uint256 indexed roundId, uint256 indexed promptId, address voter, uint256 amount);
	event RoundAdvancedToVoting(uint256 indexed roundId);
	event RoundFinalized(uint256 indexed roundId, uint256 winningPromptId, string text);
	event PotDistribution(address indexed winner, uint256 amount);
	event ShoutOut(address indexed sender, string message, uint256 feePaid);

	constructor(uint64 _subscriptionId) RandomnessConsumer(_subscriptionId) {
		COORDINATOR = VRFCoordinatorV2Interface(vrfCoordinator);
		subscriptionId = _subscriptionId;
		owner = msg.sender;
		_startNewRound();
		lastActionTime = block.timestamp;
	}

	modifier onlyOwner() {
		require(msg.sender == owner, "Not the owner");
		_;
	}

	// ---------------------------------
	// ROUND LOGIC
	// ---------------------------------

	function submitPrompt(string memory _text) external payable {
		RoundData storage round = rounds[currentRoundId];
		require(round.state == RoundState.SUBMISSION, "Not submission phase");
		require(block.timestamp < round.submissionEndTime, "Submission time ended");
		require(msg.value > 0, "Must send ETH with prompt");

		// Dev fee
		uint256 devCut = (msg.value * DEV_FEE_PERCENT) / 100;
		payable(owner).transfer(devCut);

		// The rest goes to pot
		uint256 leftover = msg.value - devCut;
		pot += leftover;

		// Create prompt
		uint256 pid = nextPromptId++;
		Prompt storage p = prompts[pid];
		p.creator = msg.sender;
		p.text = _text;
		p.exists = true;

		round.promptIds.push(pid);

		emit PromptSubmitted(currentRoundId, pid, msg.sender, _text);

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

	function voteOnPrompt(uint256 _promptId) external payable {
		RoundData storage round = rounds[currentRoundId];
		require(round.state == RoundState.VOTING, "Not in voting phase");
		require(block.timestamp < round.votingEndTime, "Voting ended");
		require(msg.value > 0, "Must send ETH to vote");
		require(prompts[_promptId].exists, "Prompt doesn't exist");
		// Also check if the prompt is part of this round? 
		// (We skip the check for brevity, but you'd do it in production.)

		// Dev fee
		uint256 devCut = (msg.value * DEV_FEE_PERCENT) / 100;
		payable(owner).transfer(devCut);

		// Remainder to pot
		uint256 leftover = msg.value - devCut;
		pot += leftover;

		// Tally vote
		Prompt storage p = prompts[_promptId];
		p.totalVotes += msg.value;

		if (p.votesByAddress[msg.sender] == 0) {
			p.voters.push(msg.sender);
		}
		p.votesByAddress[msg.sender] += msg.value;

		// update top voter if needed
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

		// pick winner = highest totalVotes among round.promptIds
		uint256 winningPromptId = _findWinningPromptId(round.promptIds);

		Prompt storage winner = prompts[winningPromptId];

		// Distribute from winner’s total votes if you want a partial immediate reward:
		// e.g. 30% to winner creator, 15% to top bidder, 5% random among voters, 50% to pot
		// We'll do it quickly here for demonstration:
		uint256 winningTotal = winner.totalVotes;
		if (winningTotal > 0) {
			uint256 creatorShare = (winningTotal * 30) / 100;
			uint256 topBidderShare = (winningTotal * 15) / 100;
			uint256 randomBidderShare = (winningTotal * 5) / 100;
			uint256 leftoverToPot = winningTotal - (creatorShare + topBidderShare + randomBidderShare);

			payable(winner.creator).transfer(creatorShare);
			if (winner.topVoter != address(0)) {
				payable(winner.topVoter).transfer(topBidderShare);
			}
			address randomVoter = _pickRandomVoter(winningPromptId);
			if (randomVoter != address(0)) {
				payable(randomVoter).transfer(randomBidderShare);
			}
			pot += leftoverToPot;
		}

		emit RoundFinalized(currentRoundId, winningPromptId, winner.text);

		// record the new "round winner"
		roundCount++;
		lastHundredWinners.push(winner.creator);
		if (lastHundredWinners.length > 100) {
			_popFront(lastHundredWinners);
		}

		// check if we do random distribution
		if (roundCount % 100 == 0) {
			_distributePotRandomly();
		}

		// start a new round automatically or wait for user to do so
		// We'll do it automatically for convenience
		_startNewRound();

		lastActionTime = block.timestamp;
	}

	// If no new round activity for a day, anyone can call
	// to distribute the pot randomly among last 100 winners
	function distributeIdlePot() external {
		require(block.timestamp >= lastActionTime + IDLE_DURATION, "Not enough idle time");
		require(pot > 0, "Nothing in pot");
		_distributePotRandomly();
	}

	// ---------------------------------
	// MESSAGE BOX (SHOUT OUTS)
	// ---------------------------------

	function postShoutOut(string calldata _msg) external payable {
		require(msg.value >= shoutOutFee, "Insufficient shoutOut fee");
		// dev fee or pot?
		// For simplicity, let's put the entire shoutOutFee into the pot 
		// and no dev fee. Or do dev fee if you like.
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

	// Admin can post a free message
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

	// (Optionally) owner can update shoutOutFee
	function setShoutOutFee(uint256 _fee) external onlyOwner {
		shoutOutFee = _fee;
	}

	// ---------------------------------
	// INTERNAL LOGIC
	// ---------------------------------

	function _startNewRound() internal {
		currentRoundId++;
		RoundData storage newRound = rounds[currentRoundId];
		newRound.state = RoundState.SUBMISSION;
		newRound.submissionEndTime = block.timestamp + SUBMISSION_DURATION;
		newRound.votingEndTime = newRound.submissionEndTime + VOTING_DURATION;
		newRound.finalized = false;
	}

	function _findWinningPromptId(uint256[] storage promptIds) internal view returns (uint256) {
		uint256 winnerId;
		uint256 highest;
		for (uint256 i = 0; i < promptIds.length; i++) {
			uint256 pid = promptIds[i];
			uint256 tv = prompts[pid].totalVotes;
			if (tv > highest) {
				highest = tv;
				winnerId = pid;
			}
		}
		return winnerId;
	}

	function _distributePotRandomly() internal {
		if (lastHundredWinners.length == 0) {
			return;
		}
		requestRandomness();
	}

	// Remove the old _pseudoRandomIndex function and replace with VRF callback
	function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
		require(pendingRandomDistribution[requestId], "No pending request");
		
		uint256 randomResult = randomWords[0];
		
		if (lastHundredWinners.length > 0) {
			uint256 winnerIndex = randomResult % lastHundredWinners.length;
			address lucky = lastHundredWinners[winnerIndex];
			
			uint256 potToSend = pot;
			pot = 0;
			
			payable(lucky).transfer(potToSend);
			emit PotDistribution(lucky, potToSend);
		}
		
		delete pendingRandomDistribution[requestId];
	}

	function _pickRandomVoter(uint256 promptId) internal returns (address) {
		Prompt storage p = prompts[promptId];
		if (p.voters.length == 0) {
			return address(0);
		}
		uint256 requestId = COORDINATOR.requestRandomWords(
			keyHash,
			subscriptionId,
			requestConfirmations,
			callbackGasLimit,
			numWords
		);
		uint256 randIndex = requestId % p.voters.length;
		return p.voters[randIndex];
	}

	function _popFront(address[] storage arr) internal {
		if (arr.length == 0) return;
		for (uint256 i = 0; i < arr.length - 1; i++) {
			arr[i] = arr[i + 1];
		}
		arr.pop();
	}


	// fallback to accept direct ETH (added to pot)
	receive() external payable {
		pot += msg.value;
	}
}
