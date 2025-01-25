// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MockVRFCoordinator {
    uint256 internal requestId = 1;
    uint256 public requestCounter;
    uint256 public mockRandomNumber = 12345;
    
    // Track requests by requestId
    mapping(uint256 => address) public consumers;
    
    event RandomWordsRequested(
        uint256 indexed requestId,
        address indexed consumer
    );

    event RandomWordsFulfilled(
        uint256 indexed requestId,
        uint256[] randomWords,
        address consumer
    );
    
    event DebugCallback(
        bool success,
        bytes data
    );

    event DebugFulfill(
        uint256 requestId,
        address consumer,
        uint256[] words
    );
    
    function requestRandomWords(
        bytes32, // keyHash
        uint64,  // subId
        uint16,  // minimumRequestConfirmations
        uint32,  // callbackGasLimit
        uint32   // numWords
    ) external returns (uint256) {
        uint256 currentId = requestId;
        requestCounter++;
        consumers[currentId] = msg.sender;
        emit RandomWordsRequested(currentId, msg.sender);
        requestId++;
        return currentId;
    }

    function fulfillRandomWords(uint256 _requestId, address consumer) external {
        require(consumers[_requestId] == consumer, "Consumer mismatch");
        
        uint256[] memory words = _getRandomWords();
        
        // Emit debug event
        emit DebugFulfill(_requestId, consumer, words);

        // First emit standard event
        emit RandomWordsRequested(_requestId, consumer);
        
        // Direct call instead of try-catch for better error visibility
        VRFConsumerBaseV2(consumer).rawFulfillRandomWords(_requestId, words);
        
        // If we get here, it succeeded
        emit RandomWordsFulfilled(_requestId, words, consumer);
        delete consumers[_requestId];
    }

    function _getRandomWords() internal view returns (uint256[] memory) {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = mockRandomNumber;
        return randomWords;
    }

    function setMockRandomNumber(uint256 _mockRandomNumber) external {
        mockRandomNumber = _mockRandomNumber;
    }
}

// Minimal interface needed for the mock
abstract contract VRFConsumerBaseV2 {
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external virtual;
}
