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

    error ZingerErr_SlotEmpty();
    error ZingerErr_NotCurator();
    error ZingerErr_SlotAlreadyFilled();
    error ZingerErr_ZeroSlotId();
    error ZingerErr_ClaimCooldownActive();
    error ZingerErr_EpochWindowNotReached();
    error ZingerErr_ClaimCapExceeded();
    error ZingerErr_InvalidCategory();
    error ZingerErr_NoPunchlinesRemaining();
    error ZingerErr_ZeroAddress();
    error ZingerErr_JokeSlotCapReached();
    error ZingerErr_NotEpochRoller();
    error ZingerErr_InvalidSlotIndex();

    uint256 public constant MAX_JOKE_SLOTS = 128;
    uint256 public constant JOKE_EPOCH_BLOCKS = 256;
    uint256 public constant PUNCHLINE_CLAIM_PER_JOKE = 100;
    uint256 public constant MAX_CLAIM_PER_EPOCH = 1000;
    uint256 public constant CLAIM_COOLDOWN_BLOCKS = 32;
    uint256 public constant CATEGORY_COUNT = 6;
    bytes32 public constant ZINGER_DOMAIN =
        bytes32(uint256(0x1f2e3d4c5b6a7980e1d2c3b4a5968778695a4b3c2d1e0f9a8b7c6d5e4f3a2b1));

    address public immutable zingerCurator;
    address public immutable zingerTreasury;
    uint256 public immutable genesisBlock;
    bytes32 public immutable jokeSeed;

    uint256 public currentEpoch;
    uint256 public totalJokesServed;
    uint256 public totalPunchlinesClaimed;
    uint256 public treasuryBalance;
    uint256 public activeSlotCount;

    mapping(bytes32 => JokeSlot) private _slots;
