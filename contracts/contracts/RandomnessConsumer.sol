// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";

abstract contract RandomnessConsumer is VRFConsumerBaseV2 {
    VRFCoordinatorV2Interface COORDINATOR;
    
    // Network specific values
    address public vrfCoordinator = 0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D;
    bytes32 keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
    uint64 public subscriptionId;
    uint32 callbackGasLimit = 100000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;

    // VRF tracking
    mapping(uint256 => bool) public pendingRandomDistribution;

    // Add debug event
    event CoordinatorUpdated(address oldCoordinator, address newCoordinator);

    // Change constructor to allow coordinator override
    constructor(uint64 _subscriptionId, address _coordinator) VRFConsumerBaseV2(_coordinator) {
        vrfCoordinator = _coordinator;
        COORDINATOR = VRFCoordinatorV2Interface(_coordinator);
        subscriptionId = _subscriptionId;
    }

    function requestRandomness() internal returns (uint256 requestId) {
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        pendingRandomDistribution[requestId] = true;
        return requestId;
    }

    function _setVRFCoordinator(address _coordinator) internal {
        address oldCoordinator = vrfCoordinator;
        vrfCoordinator = _coordinator;
        COORDINATOR = VRFCoordinatorV2Interface(_coordinator);
        
        // Update the base contract's coordinator using assembly
        assembly {
            // VRFConsumerBaseV2 storage slot 0 holds the coordinator address
            sstore(0, _coordinator)
        }
        
        emit CoordinatorUpdated(oldCoordinator, _coordinator);
    }
}
