// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MockVRFCoordinator {
    uint256 internal requestId = 1;
    uint256 public requestCounter;
    uint256 public mockRandomNumber = 12345;
    
    event RandomWordsRequested(
        uint256 indexed requestId,
        address indexed consumer
    );

    event RandomWordsFulfilled(
        uint256 indexed requestId,
        uint256[] randomWords
    );
    
    function requestRandomWords(
        bytes32, // keyHash
        uint64,  // subId
        uint16,  // minimumRequestConfirmations
        uint32,  // callbackGasLimit
        uint32   // numWords
    ) external returns (uint256) {
        requestCounter++;
        emit RandomWordsRequested(requestId, msg.sender);
        return requestId++;
    }

    function fulfillRandomWords(uint256 _requestId, address consumer) external {
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = mockRandomNumber;
        
        emit RandomWordsFulfilled(_requestId, randomWords);
        VRFConsumerBaseV2(consumer).rawFulfillRandomWords(_requestId, randomWords);
    }

    // Test helper to set the mock random number
    function setMockRandomNumber(uint256 _mockRandomNumber) external {
        mockRandomNumber = _mockRandomNumber;
    }
}

// Minimal interface needed for the mock
abstract contract VRFConsumerBaseV2 {
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external virtual;
}
