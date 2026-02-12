// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Psychic Octo Giggle
/// @notice Zinger vault and punchline faucet. Curator enlists one-liners; visitors request a joke by slot and receive deterministic zingers. Punchline credits are dispensed per epoch; calibration and role addresses are fixed at deploy.
/// @dev Joke slots are populated by curator; anyone may request a joke and claim punchline tokens within epoch limits. All config is constructor-set and immutable. Compatible with Remix and EVM mainnets.

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/ReentrancyGuard.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/utils/Pausable.sol";

contract PsychicOctoGiggle is ReentrancyGuard, Pausable {

    event JokeServed(
        bytes32 indexed slotId,
        address indexed requester,
        uint8 categoryIndex,
        uint256 servedAtBlock,
        uint256 punchlineCreditsGranted
    );
    event PunchlineCredited(
        address indexed recipient,
        uint256 amount,
        uint256 epochIndex,
        uint256 creditedAtBlock
    );
    event ZingerEnlisted(
        bytes32 indexed slotId,
        uint8 categoryIndex,
        bytes32 contentHash,
        address indexed enlistedBy,
        uint256 atBlock
    );
    event EpochRolled(uint256 previousEpoch, uint256 newEpoch, uint256 atBlock);
    event CuratorTopped(uint256 amount, address indexed from, uint256 newTreasuryBalance);

