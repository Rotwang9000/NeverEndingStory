// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./RandomnessConsumer.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/*
   Multi-prompt voting, unstoppable time-based rounds,
   random pot distribution every 100 winners or if idle for a day,
   plus a "shout out" message board with a small fee.
*/

contract NeverEndingStory is RandomnessConsumer, ReentrancyGuard {
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
		uint256 submissions;         // how many prompts submitted so far
		uint256 totalVotingAmount;   // how much ETH has been voted so far
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

	// Add new state variables for tracking random voter requests
	mapping(uint256 => uint256) public pendingRandomVoterPromptId;
	mapping(uint256 => address) public pendingRandomVoterWinner;

	// Add these state variables after the existing state variables
	struct PendingReward {
		address recipient;
		uint256 amount;
	}
	mapping(uint256 => PendingReward[]) public pendingRewards;

	// Add new state variables for limiting submissions and voting
	uint256 public maxSubmissions;
	uint256 public maxVotingAmount;

	// Events
	event PromptSubmitted(uint256 indexed roundId, uint256 promptId, address indexed creator, string text);
	event VoteCast(uint256 indexed roundId, uint256 indexed promptId, address voter, uint256 amount);
	event RoundAdvancedToVoting(uint256 indexed roundId);
	event RoundFinalized(uint256 indexed roundId, uint256 winningPromptId, string text);
	event PotDistribution(address indexed winner, uint256 amount);
	event ShoutOut(address indexed sender, string message, uint256 feePaid);

	// Add new events for debugging
	event TransferFailed(address recipient, uint256 amount);
	event TransferSucceeded(address recipient, uint256 amount);

	// Add new debug events
	event DebugTransfer(
		string action,
		address to,
		uint256 amount,
		uint256 currentPot
	);

	// Add a new event for high gas transfers
	event HighGasTransfer(address to, uint256 amount);

	// Add new event for round count debugging
	event DebugCount(string msg, uint256 count);

	// Add new debug events
	event DebugPot(string msg, uint256 amount);
	event DebugAddress(string msg, address addr);

	event DebugBalance(string msg, uint256 balance, uint256 pot);

	// Add event for tracking funds
	event FundsTracking(
		string action,
		uint256 amount,
		uint256 pot,
		uint256 balance
	);

	constructor(uint64 _subscriptionId, address _coordinator) 
        RandomnessConsumer(_subscriptionId, _coordinator) 
    {
        owner = msg.sender;
        _startNewRound();
        lastActionTime = block.timestamp;
    }

	modifier onlyOwner() {
		require(msg.sender == owner, "Not the owner");
		_;
	}

	// Add this function after the constructor
	function setVRFCoordinator(address _coordinator) external onlyOwner {
		_setVRFCoordinator(_coordinator);
	}

	// Add setter functions for these limits
	function setMaxSubmissions(uint256 _maxSubmissions) external onlyOwner {
		maxSubmissions = _maxSubmissions;
	}

	function setMaxVotingAmount(uint256 _maxVotingAmount) external onlyOwner {
		maxVotingAmount = _maxVotingAmount;
	}

	// Add transferOwnership function
	function transferOwnership(address newOwner) external onlyOwner {
		owner = newOwner;
	}

	// ---------------------------------
	// ROUND LOGIC
	// ---------------------------------

	function submitPrompt(string memory _text) external payable nonReentrant {
		RoundData storage round = rounds[currentRoundId];
		require(round.state == RoundState.SUBMISSION, "Not submission phase");
		require(block.timestamp < round.submissionEndTime, "Submission time ended");
		require(msg.value > 0, "Must send ETH with prompt");

		 // Enforce maximum submissions if set
        if (maxSubmissions > 0) {
            require(round.submissions < maxSubmissions, "Max number of submissions reached");
        }

		// Handle fees first
		_handlePromptFees(msg.value);

		// Create prompt
		uint256 pid = nextPromptId++;
		Prompt storage p = prompts[pid];
		p.creator = msg.sender;
		p.text = _text;
		p.exists = true;

		round.promptIds.push(pid);
		round.submissions++;

		// Apply submission ETH as a vote on its own prompt
		// Enforce maxVotingAmount if set
		if (maxVotingAmount > 0) {
			require(round.totalVotingAmount + msg.value <= maxVotingAmount, "Max voting limit reached");
		}
		p.totalVotes += msg.value;
		if (p.votesByAddress[msg.sender] == 0) {
			p.voters.push(msg.sender);
		}
		p.votesByAddress[msg.sender] += msg.value;
		if (p.votesByAddress[msg.sender] > p.topVoterAmount) {
			p.topVoterAmount = p.votesByAddress[msg.sender];
			p.topVoter = msg.sender;
		}
		round.totalVotingAmount += msg.value;

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

    function voteOnPrompt(uint256 _promptId) external payable nonReentrant {
        // Validation first
        RoundData storage round = rounds[currentRoundId];
        require(round.state == RoundState.VOTING, "Not in voting phase");
        require(block.timestamp < round.votingEndTime, "Voting ended");
        require(msg.value > 0, "Must send ETH to vote");
        require(prompts[_promptId].exists, "Prompt doesn't exist");

        // Update state before external calls
        Prompt storage p = prompts[_promptId];
        p.totalVotes += msg.value;
        round.totalVotingAmount += msg.value;

        if (p.votesByAddress[msg.sender] == 0) {
            p.voters.push(msg.sender);
        }
        p.votesByAddress[msg.sender] += msg.value;

        if (p.votesByAddress[msg.sender] > p.topVoterAmount) {
            p.topVoterAmount = p.votesByAddress[msg.sender];
            p.topVoter = msg.sender;
        }

        // Calculate fees
        uint256 devCut = (msg.value * DEV_FEE_PERCENT) / 100;
        uint256 leftover = msg.value - devCut;
        pot += leftover;

        // External call last, but capture revert reason:
        (bool success, bytes memory data) = payable(owner).call{value: devCut}("");
        if (!success) {
            if (data.length > 0) {
                assembly {
                    revert(add(32, data), mload(data))
                }
            } else {
                revert("Dev fee transfer failed");
            }
        }

        emit VoteCast(currentRoundId, _promptId, msg.sender, msg.value);
        lastActionTime = block.timestamp;
    }

	function finalizeRound() external nonReentrant {
		RoundData storage round = rounds[currentRoundId];
		require(round.state == RoundState.VOTING, "Not in voting phase");
		require(block.timestamp >= round.votingEndTime, "Voting not ended");
		require(!round.finalized, "Already finalized");

		round.finalized = true;
		round.state = RoundState.ENDED;

		uint256 winningPromptId = _findWinningPromptId(round.promptIds);
		Prompt storage winner = prompts[winningPromptId];

		if (winner.totalVotes > 0) {
			// Calculate shares
			uint256 totalVotes = winner.totalVotes;
			uint256 creatorShare = (totalVotes * 30) / 100;
			uint256 topBidderShare = (totalVotes * 15) / 100;
			uint256 randomBidderShare = (totalVotes * 5) / 100;

			// Sync pot before transfers
			_syncPotWithBalance();

			// Send immediate rewards
			if (creatorShare > 0) {
				payable(winner.creator).transfer(creatorShare);
				_syncPotWithBalance();
			}

			if (topBidderShare > 0 && winner.topVoter != address(0)) {
				payable(winner.topVoter).transfer(topBidderShare);
				_syncPotWithBalance();
			}

			// Handle random voter reward if any
			if (randomBidderShare > 0) {
				uint256 requestId = _pickRandomVoter(winningPromptId);
				if (requestId > 0) {
					pendingRewards[requestId].push(PendingReward({
						recipient: address(0),
						amount: randomBidderShare
					}));
				}
			}
		}

		// Update winners list
		roundCount++;
		lastHundredWinners.push(winner.creator);
		if (lastHundredWinners.length > 100) {
			_popFront(lastHundredWinners);
		}

		emit RoundFinalized(currentRoundId, winningPromptId, winner.text);
		
		// Random pot distribution check
		if (roundCount >= 100) {
			emit DebugCount("distributing pot at count", roundCount);
			uint256 currentBalance = address(this).balance;
			if (currentBalance > 0) {
				_distributePotRandomly();
			}
		}

		_startNewRound();
		lastActionTime = block.timestamp;
	}

	// If no new round activity for a day, anyone can call
	// to distribute the pot randomly among last 100 winners
	function distributeIdlePot() external nonReentrant {
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
		if (lastHundredWinners.length == 0) return;
		
		 // Sync before distribution
        _syncPotWithBalance();
        
        if (pot == 0) return;
		
		emit DebugCount("requesting random for distribution", pot);
		requestRandomness();
	}

	// Remove the old _pseudoRandomIndex function and replace with VRF callback
	function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
		// Ensure pot is in sync with balance
        rebalancePot();
        
		uint256 randomResult = randomWords[0];
		
		emit DebugCount("fulfilling random", requestId);
		
		// Handle pot distribution
		if (pendingRandomDistribution[requestId]) {
			emit DebugCount("handling pot distribution", pot);
			
			if (lastHundredWinners.length > 0) {
				uint256 winnerIndex = randomResult % lastHundredWinners.length;
				address lucky = lastHundredWinners[winnerIndex];
				emit DebugAddress("lucky winner", lucky);
				
				uint256 potToSend = pot;
				pot = 0;
				(bool success,) = payable(lucky).call{value: potToSend}("");
				if (!success) {
					pot = potToSend;
				} else {
					roundCount = 0;
				}
			}
			
			delete pendingRandomDistribution[requestId];
		}
		// Handle random voter selection
		else if (pendingRandomVoterPromptId[requestId] > 0) {
			uint256 promptId = pendingRandomVoterPromptId[requestId];
			Prompt storage p = prompts[promptId];
			
			if (p.voters.length > 0) {
				uint256 randIndex = randomResult % p.voters.length;
				address voter = p.voters[randIndex];
				
				// Process any pending rewards
				PendingReward[] storage rewards = pendingRewards[requestId];
				for (uint256 i = 0; i < rewards.length; i++) {
					if (rewards[i].amount > 0) {
						_safeTransfer(voter, rewards[i].amount);
					}
				}
				delete pendingRewards[requestId];
			}
			
			delete pendingRandomVoterPromptId[requestId];
		}
	}

	// Update _pickRandomVoter to return requestId
	function _pickRandomVoter(uint256 promptId) internal returns (uint256) {
		Prompt storage p = prompts[promptId];
		if (p.voters.length == 0) {
			return 0;
		}
		
		uint256 requestId = COORDINATOR.requestRandomWords(
			keyHash,
			subscriptionId,
			requestConfirmations,
			callbackGasLimit,
			numWords
		);
		
		pendingRandomVoterPromptId[requestId] = promptId;
		return requestId;
	}

	function _popFront(address[] storage arr) internal {
		if (arr.length == 0) return;
		for (uint256 i = 0; i < arr.length - 1; i++) {
			arr[i] = arr[i + 1];
		}
		arr.pop();
	}

	// Simplify safe transfer - just use what's available
	function _safeTransfer(address to, uint256 amount) internal returns (bool) {
		if (to == address(0) || amount == 0) return false;
		
		 // Sync before transfer
        _syncPotWithBalance();
        
        // Only transfer what's actually available
        uint256 actualAmount = amount > pot ? pot : amount;
        if (actualAmount == 0) return false;
        
        // Update pot first
        pot -= actualAmount;
		
		(bool success, ) = payable(to).call{value: actualAmount}("");
		
		if (!success) {
			pot += actualAmount;  // Restore on failure
			emit TransferFailed(to, actualAmount);
			return false;
		}
		
		emit TransferSucceeded(to, actualAmount);
		return true;
	}

	// Add function to verify pot matches balance
    function verifyPotBalance() public view returns (bool) {
        return pot <= address(this).balance;
    }

	// Add view function for testing
    function getLastHundredWinnersLength() external view returns (uint256) {
        return lastHundredWinners.length;
    }

	// Simplified receive function - no pot tracking needed
    receive() external payable {
        // Just accept the payment
    }

	// Add function to fix pot if it gets out of sync
    function emergencyResetPot() external onlyOwner {
        pot = address(this).balance;
    }

	// Add pot rebalancing function
    function rebalancePot() public {
        uint256 balance = address(this).balance;
        if (pot > balance) {
            pot = balance;
            emit DebugBalance("pot rebalanced", balance, pot);
        }
    }

	// Add a function to check contract's real balance
    function getActualBalance() public view returns (uint256) {
        return address(this).balance;
    }

	// Add a function to check ETH flow for prompts
    function _handlePromptFees(uint256 totalAmount) internal returns (uint256) {
        uint256 devCut = (totalAmount * DEV_FEE_PERCENT) / 100;
        uint256 leftover = totalAmount - devCut;
        
        emit FundsTracking("fees-start", totalAmount, pot, address(this).balance);

        (bool success, bytes memory data) = payable(owner).call{value: devCut}("");
        if (!success) {
            if (data.length > 0) {
                assembly {
                    revert(add(32, data), mload(data))
                }
            } else {
                revert("Dev fee transfer failed");
            }
        }

        _syncPotWithBalance();
        pot += leftover;

        emit FundsTracking("fees-end", leftover, pot, address(this).balance);
        return leftover;
    }

	// Add new function to sync pot with actual balance
    function _syncPotWithBalance() internal {
        uint256 currentBalance = address(this).balance;
        if (pot > currentBalance) {
            pot = currentBalance;
            emit DebugBalance("pot synced", currentBalance, pot);
        }
    }
}
