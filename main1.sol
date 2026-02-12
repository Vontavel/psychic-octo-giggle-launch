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
        JokeSlot storage s = _slots[slotId];
        if (!s.filled) revert ZingerErr_SlotEmpty();
        _maybeRollEpoch();
        uint256 claim = PUNCHLINE_CLAIM_PER_JOKE;
        uint256 alreadyThisEpoch = _claimedThisEpoch[msg.sender];
        if (alreadyThisEpoch + claim > MAX_CLAIM_PER_EPOCH) {
            claim = alreadyThisEpoch >= MAX_CLAIM_PER_EPOCH ? 0 : MAX_CLAIM_PER_EPOCH - alreadyThisEpoch;
        }
        if (block.number < _lastClaimBlock[msg.sender] + CLAIM_COOLDOWN_BLOCKS && alreadyThisEpoch > 0) {
            claim = 0;
        }
        if (claim > 0) {
            punchlineBalance[msg.sender] += claim;
            totalPunchlinesClaimed += claim;
            _claimedThisEpoch[msg.sender] += claim;
            _lastClaimBlock[msg.sender] = block.number;
            emit PunchlineCredited(msg.sender, claim, currentEpoch, block.number);
        }
        totalJokesServed++;
        emit JokeServed(slotId, msg.sender, s.categoryIndex, block.number, claim);
        return (s.categoryIndex, s.contentHash, claim);
    }

    function requestJokeByIndex(uint256 slotIndex) external whenNotPaused nonReentrant returns (bytes32 slotId, uint8 categoryIndex, bytes32 contentHash, uint256 creditsGranted) {
        if (slotIndex >= _slotIdList.length) revert ZingerErr_InvalidSlotIndex();
        slotId = _slotIdList[slotIndex];
        JokeSlot storage s = _slots[slotId];
        if (!s.filled) revert ZingerErr_SlotEmpty();
        _maybeRollEpoch();
        uint256 claim = PUNCHLINE_CLAIM_PER_JOKE;
        uint256 alreadyThisEpoch = _claimedThisEpoch[msg.sender];
        if (alreadyThisEpoch + claim > MAX_CLAIM_PER_EPOCH) {
            claim = alreadyThisEpoch >= MAX_CLAIM_PER_EPOCH ? 0 : MAX_CLAIM_PER_EPOCH - alreadyThisEpoch;
        }
        if (block.number < _lastClaimBlock[msg.sender] + CLAIM_COOLDOWN_BLOCKS && alreadyThisEpoch > 0) {
            claim = 0;
        }
        if (claim > 0) {
            punchlineBalance[msg.sender] += claim;
            totalPunchlinesClaimed += claim;
            _claimedThisEpoch[msg.sender] += claim;
            _lastClaimBlock[msg.sender] = block.number;
            emit PunchlineCredited(msg.sender, claim, currentEpoch, block.number);
        }
        totalJokesServed++;
        emit JokeServed(slotId, msg.sender, s.categoryIndex, block.number, claim);
        return (slotId, s.categoryIndex, s.contentHash, claim);
    }

    function _maybeRollEpoch() private {
        uint256 epochFromGenesis = (block.number - genesisBlock) / JOKE_EPOCH_BLOCKS;
        if (epochFromGenesis > currentEpoch && !_epochAdvanced[epochFromGenesis]) {
            uint256 prev = currentEpoch;
            currentEpoch = epochFromGenesis;
            _epochAdvanced[epochFromGenesis] = true;
            emit EpochRolled(prev, currentEpoch, block.number);
        }
    }

    function rollEpoch() external onlyEpochRoller whenNotPaused {
        uint256 epochFromGenesis = (block.number - genesisBlock) / JOKE_EPOCH_BLOCKS;
        if (epochFromGenesis <= currentEpoch) revert ZingerErr_EpochWindowNotReached();
        uint256 prev = currentEpoch;
        currentEpoch = epochFromGenesis;
        _epochAdvanced[epochFromGenesis] = true;
        emit EpochRolled(prev, currentEpoch, block.number);
    }

    function topTreasury() external payable whenNotPaused {
        if (msg.value == 0) return;
        treasuryBalance += msg.value;
        emit CuratorTopped(msg.value, msg.sender, treasuryBalance);
    }

    function withdrawTreasury(uint256 amount) external onlyCurator nonReentrant {
        if (amount > treasuryBalance) amount = treasuryBalance;
        if (amount == 0) return;
        treasuryBalance -= amount;
        (bool ok,) = payable(zingerTreasury).call{value: amount}("");
        require(ok, "ZingerErr_WithdrawFailed");
    }

    function pause() external onlyCurator {
        _pause();
    }

    function unpause() external onlyCurator {
        _unpause();
    }

    function getJokeSlot(bytes32 slotId) external view returns (uint8 categoryIndex, bytes32 contentHash, uint256 enlistedAtBlock, bool filled) {
        JokeSlot storage s = _slots[slotId];
        return (s.categoryIndex, s.contentHash, s.enlistedAtBlock, s.filled);
    }

    function getJokeSlotByIndex(uint256 slotIndex) external view returns (bytes32 slotId, uint8 categoryIndex, bytes32 contentHash, uint256 enlistedAtBlock, bool filled) {
        if (slotIndex >= _slotIdList.length) revert ZingerErr_InvalidSlotIndex();
        slotId = _slotIdList[slotIndex];
        JokeSlot storage s = _slots[slotId];
        return (s.slotId, s.categoryIndex, s.contentHash, s.enlistedAtBlock, s.filled);
    }

    function getSlotIdListLength() external view returns (uint256) {
        return _slotIdList.length;
    }

    function getSlotIdAt(uint256 index) external view returns (bytes32) {
        if (index >= _slotIdList.length) revert ZingerErr_InvalidSlotIndex();
        return _slotIdList[index];
    }

    function claimableFor(address account) external view returns (uint256) {
        uint256 already = _claimedThisEpoch[account];
        if (already >= MAX_CLAIM_PER_EPOCH) return 0;
        if (block.number < _lastClaimBlock[account] + CLAIM_COOLDOWN_BLOCKS && already > 0) return 0;
        return PUNCHLINE_CLAIM_PER_JOKE;
    }

    function currentEpochBlockWindow() external view returns (uint256 startBlock, uint256 endBlock) {
        startBlock = genesisBlock + currentEpoch * JOKE_EPOCH_BLOCKS;
        endBlock = genesisBlock + (currentEpoch + 1) * JOKE_EPOCH_BLOCKS - 1;
    }

    function getCategoryName(uint8 categoryIndex) external pure returns (string memory) {
        if (categoryIndex >= CATEGORY_COUNT) return "";
        string[6] memory names = ["Tech", "Animals", "Food", "Work", "Math", "Misc"];
        return names[categoryIndex];
    }

    function getJokeTextByCategory(uint8 categoryIndex) external pure returns (string memory) {
        if (categoryIndex >= CATEGORY_COUNT) return "";
        string[6] memory jokes = [
            "Why do programmers prefer dark mode? Because light attracts bugs.",
            "What do you call a bear with no teeth? A gummy bear.",
            "Why did the tomato turn red? It saw the salad dressing.",
            "Why did the scarecrow get promoted? He was outstanding in his field.",
            "Why was the equal sign so humble? He knew he wasn't less than or greater than anyone.",
            "What do you call a fake noodle? An impasta."
        ];
        return jokes[categoryIndex];
    }

    function getJokeTextByIndex(uint256 jokeIndex) external pure returns (string memory) {
        string[18] memory allJokes = [
            "Why do programmers prefer dark mode? Because light attracts bugs.",
            "What do you call a bear with no teeth? A gummy bear.",
            "Why did the tomato turn red? It saw the salad dressing.",
            "Why did the scarecrow get promoted? He was outstanding in his field.",
            "Why was the equal sign so humble? He knew he wasn't less than or greater than anyone.",
            "What do you call a fake noodle? An impasta.",
            "Why did the doctor quit? He lost his patients.",
            "Why did the student eat his homework? The teacher said it was a piece of cake.",
            "Why don't ghosts like rain? It dampens their spirits.",
            "Knock knock. Who's there? Octopus. Octopus who? Octopus me, you're not so tough.",
            "A byte walks into a bar. Bartender says: We don't serve bytes here.",
            "Why did the octopus blush? It saw the ocean's bottom.",
            "How does an octopus go to war? Well-armed.",
            "Why did the blockchain break up? It had too many forks.",
            "What do you call a snake that is 3.14 meters long? A pi-thon.",
            "Why do Java developers wear glasses? Because they don't C#.",
            "How many tickles does it take to make an octopus laugh? Ten tickles.",
            "Why did the function break up with the variable? It had too many arguments."
        ];
        if (jokeIndex >= allJokes.length) return "";
        return allJokes[jokeIndex];
    }

    function getRandomishSlotId(uint256 nonce) external view returns (bytes32) {
        if (_slotIdList.length == 0) return bytes32(0);
        uint256 idx = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, nonce, msg.sender))) % _slotIdList.length;
        return _slotIdList[idx];
    }

    function totalPunchlineSupply() external view returns (uint256) {
        return totalPunchlinesClaimed;
    }

    function getEpochProgress() external view returns (uint256 blocksIntoEpoch, uint256 blocksRemaining) {
        uint256 epochStart = genesisBlock + currentEpoch * JOKE_EPOCH_BLOCKS;
        if (block.number < epochStart) {
            blocksIntoEpoch = 0;
            blocksRemaining = epochStart - block.number;
        } else {
            uint256 epochEnd = genesisBlock + (currentEpoch + 1) * JOKE_EPOCH_BLOCKS - 1;
            if (block.number >= epochEnd) {
                blocksIntoEpoch = JOKE_EPOCH_BLOCKS;
                blocksRemaining = 0;
            } else {
                blocksIntoEpoch = block.number - epochStart + 1;
                blocksRemaining = epochEnd - block.number;
            }
        }
    }

    function getSlotIdsForCategory(uint8 categoryIndex) external view returns (bytes32[] memory) {
        if (categoryIndex >= CATEGORY_COUNT) return new bytes32[](0);
        uint256 count = 0;
        for (uint256 i = 0; i < _slotIdList.length; i++) {
            if (_slots[_slotIdList[i]].categoryIndex == categoryIndex) count++;
        }
        bytes32[] memory out = new bytes32[](count);
        uint256 j = 0;
        for (uint256 i = 0; i < _slotIdList.length; i++) {
            if (_slots[_slotIdList[i]].categoryIndex == categoryIndex) {
                out[j] = _slotIdList[i];
                j++;
            }
        }
        return out;
    }

    function getContractMeta() external view returns (
        uint256 slotCount,
        uint256 jokesServed,
        uint256 punchlinesInCirculation,
        uint256 epoch,
        uint256 genesis
    ) {
        return (
            activeSlotCount,
            totalJokesServed,
            totalPunchlinesClaimed,
            currentEpoch,
            genesisBlock
        );
    }

    function canClaim(address account) external view returns (bool) {
        if (_claimedThisEpoch[account] >= MAX_CLAIM_PER_EPOCH) return false;
        if (_lastClaimBlock[account] != 0 && block.number < _lastClaimBlock[account] + CLAIM_COOLDOWN_BLOCKS) return false;
        return true;
    }

    function nextClaimBlock(address account) external view returns (uint256) {
        if (_lastClaimBlock[account] == 0) return block.number;
        uint256 next = _lastClaimBlock[account] + CLAIM_COOLDOWN_BLOCKS;
        return block.number >= next ? block.number : next;
    }
}
