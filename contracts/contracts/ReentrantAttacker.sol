// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface INeverEndingStory {
    function submitPrompt(string memory _text) external payable;
    function voteOnPrompt(uint256 _promptId) external payable;
    function finalizeRound() external;
    function distributeIdlePot() external;
}

contract ReentrantAttacker {
    INeverEndingStory public target;
    bool private inFallback;
    uint8 public attackMode; // 1 = submit, 2 = vote

    constructor(address _target) {
        target = INeverEndingStory(_target);
    }

    function attackSubmitPrompt() external payable {
        attackMode = 1;
        target.submitPrompt{value: msg.value}("Hacked!");
    }

    function attackVoteOnPrompt(uint256 _promptId) external payable {
        attackMode = 2;
        target.voteOnPrompt{value: msg.value}(_promptId);
    }

    function attackFinalizeRound() external {
        attackMode = 3;
        INeverEndingStory(target).finalizeRound();
    }

    function attackDistributeIdlePot() external {
        attackMode = 4;
        INeverEndingStory(target).distributeIdlePot();
    }

    function attackReceive() external payable {
        attackMode = 5;
        (bool success,) = address(target).call{value: msg.value}("");
        require(success, "Transfer failed");
    }

    receive() external payable {
        if (!inFallback) {
            inFallback = true;
            
            if (attackMode == 2) {
                // Try to reenter voteOnPrompt
                try INeverEndingStory(target).voteOnPrompt{value: 0.1 ether, gas: 300000}(0) {
                    revert("Reentrancy protection failed");
                } catch Error(string memory reason) {
                    require(
                        keccak256(bytes(reason)) == keccak256(bytes("ReentrancyGuard: reentrant call")),
                        "Wrong error message"
                    );
                    revert(reason);
                }
            } 
            else if (attackMode == 3) {
                // Try to reenter during finalization
                INeverEndingStory(target).finalizeRound();
            }
            else if (attackMode == 4) {
                // Try to reenter during pot distribution
                INeverEndingStory(target).distributeIdlePot();
            }
            else if (attackMode == 5) {
                // Try to reenter via receive
                (bool success,) = address(target).call{value: 0.1 ether}("");
                require(success, "Transfer failed");
            }
            
            inFallback = false;
        }
    }
}