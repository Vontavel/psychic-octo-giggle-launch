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
    mapping(address => uint256) public punchlineBalance;
    mapping(address => uint256) private _lastClaimBlock;
    mapping(address => uint256) private _claimedThisEpoch;
    mapping(uint256 => bool) private _epochAdvanced;
    bytes32[] private _slotIdList;

    struct JokeSlot {
        bytes32 slotId;
        uint8 categoryIndex;
        bytes32 contentHash;
        uint256 enlistedAtBlock;
        bool filled;
    }

    modifier onlyCurator() {
        if (msg.sender != zingerCurator) revert ZingerErr_NotCurator();
        _;
    }

    modifier onlyEpochRoller() {
        if (msg.sender != zingerCurator && msg.sender != zingerTreasury) revert ZingerErr_NotEpochRoller();
        _;
    }

    constructor() {
        zingerCurator = address(0x8a3fE91bC2d4567e0F1a9c8B4e7D2f6A3c0b5E1);
        zingerTreasury = address(0x1d7F4e9A2c6b0E8f3a5C1d9B7e4F2a6c0D8b3f);
        genesisBlock = block.number;
        jokeSeed = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, block.chainid));
        currentEpoch = 0;
        totalJokesServed = 0;
        totalPunchlinesClaimed = 0;
        treasuryBalance = 0;
        activeSlotCount = 0;
        _seedInitialJokes();
    }

    function _seedInitialJokes() private {
        bytes32[] memory ids = new bytes32[](12);
        ids[0] = keccak256("zinger_0_tech");
        ids[1] = keccak256("zinger_1_animal");
        ids[2] = keccak256("zinger_2_food");
        ids[3] = keccak256("zinger_3_work");
        ids[4] = keccak256("zinger_4_math");
        ids[5] = keccak256("zinger_5_weather");
        ids[6] = keccak256("zinger_6_doctor");
        ids[7] = keccak256("zinger_7_school");
        ids[8] = keccak256("zinger_8_ghost");
        ids[9] = keccak256("zinger_9_knock");
        ids[10] = keccak256("zinger_10_bar");
        ids[11] = keccak256("zinger_11_octopus");
        uint8[] memory cats = new uint8[](12);
        cats[0] = 0; cats[1] = 1; cats[2] = 2; cats[3] = 3; cats[4] = 4; cats[5] = 5;
        cats[6] = 0; cats[7] = 1; cats[8] = 2; cats[9] = 3; cats[10] = 4; cats[11] = 5;
        bytes32[] memory hashes = new bytes32[](12);
        hashes[0] = keccak256("Why do programmers prefer dark mode? Because light attracts bugs.");
        hashes[1] = keccak256("What do you call a bear with no teeth? A gummy bear.");
        hashes[2] = keccak256("Why did the tomato turn red? It saw the salad dressing.");
        hashes[3] = keccak256("Why did the scarecrow get promoted? He was outstanding in his field.");
        hashes[4] = keccak256("Why was the equal sign so humble? He knew he wasn't less than or greater than anyone.");
        hashes[5] = keccak256("What do you call a fake noodle? An impasta.");
        hashes[6] = keccak256("Why did the doctor quit? He lost his patients.");
        hashes[7] = keccak256("Why did the student eat his homework? The teacher said it was a piece of cake.");
        hashes[8] = keccak256("Why don't ghosts like rain? It dampens their spirits.");
        hashes[9] = keccak256("Knock knock. Who's there? Octopus. Octopus who? Octopus me, you're not so tough.");
        hashes[10] = keccak256("A byte walks into a bar. Bartender says: We don't serve bytes here. Byte says: Fine, I'll have a nibble.");
        hashes[11] = keccak256("Why did the octopus blush? It saw the ocean's bottom.");
        for (uint256 i = 0; i < ids.length && activeSlotCount < MAX_JOKE_SLOTS; i++) {
            if (_slots[ids[i]].filled) continue;
            _slots[ids[i]] = JokeSlot({
                slotId: ids[i],
                categoryIndex: cats[i],
                contentHash: hashes[i],
                enlistedAtBlock: block.number,
                filled: true
            });
            _slotIdList.push(ids[i]);
            activeSlotCount++;
            emit ZingerEnlisted(ids[i], cats[i], hashes[i], zingerCurator, block.number);
        }
    }

    function enlistZinger(bytes32 slotId, uint8 categoryIndex, bytes32 contentHash)
        external
        onlyCurator
        whenNotPaused
        nonReentrant
    {
        if (slotId == bytes32(0)) revert ZingerErr_ZeroSlotId();
        if (activeSlotCount >= MAX_JOKE_SLOTS) revert ZingerErr_JokeSlotCapReached();
        if (categoryIndex >= CATEGORY_COUNT) revert ZingerErr_InvalidCategory();
        JokeSlot storage s = _slots[slotId];
        if (s.filled) revert ZingerErr_SlotAlreadyFilled();
        s.slotId = slotId;
        s.categoryIndex = categoryIndex;
        s.contentHash = contentHash;
        s.enlistedAtBlock = block.number;
        s.filled = true;
        _slotIdList.push(slotId);
        activeSlotCount++;
        emit ZingerEnlisted(slotId, categoryIndex, contentHash, msg.sender, block.number);
    }

    function requestJoke(bytes32 slotId) external whenNotPaused nonReentrant returns (uint8 categoryIndex, bytes32 contentHash, uint256 creditsGranted) {
        if (slotId == bytes32(0)) revert ZingerErr_ZeroSlotId();
