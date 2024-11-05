// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
/** Function Structure:
 *  CEI: Checks, Effects, Interactions Pattern
 * 1. Checks (requires,conditionals)
 * 2. Effect(Internal Contract State)
 * 3. Interactions (External Contract Interactions)
 */

// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title Sample Raffle Contract
 * @author Oazed Lium
 * @notice This contract is for creating a simple raffle
 * @dev Implements Chainlink VRFv2.5
 */
contract Raffle is VRFConsumerBaseV2Plus {
    /** Errors */
    error Raffle__NotEnoughETHSent();
    error Raffle__TransferFailed();
    error Raffle__RaffleNotOpen();
    error Raffle__UpkeepNotNeeded(
        uint256 balance,
        uint256 playersLength,
        uint256 raffleState
    );

    /** Type Declarations */
    enum RaffleState {
        OPEN, // can create an integer 0
        CALCULATING // 1
    }
    /** State Variables */
    uint256 private immutable i_entranceFee;
    // @dev the duration of the lottery in seconds
    uint256 private immutable i_interval;
    address payable[] private s_players; // array of players
    // @dev after picking a winner how much time has passed will be stored
    uint256 private s_lastTimeStamp;
    bytes32 private immutable i_keyHash;
    uint256 private immutable i_subscriptionId;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private immutable i_callbackGasLimit;
    uint32 private constant NUM_WORDS = 1;
    address private s_recentWinner;
    RaffleState private s_raffleState; // start as open

    /** Events */
    event RaffleEntered(address indexed player); // A new address and a new player has entered the raffle
    event WinnerPicked(address indexed winner);
    event RequestedRaffleWinner(uint256 indexed requestId);

    constructor(
        uint256 entranceFee,
        uint256 interval,
        address vrfCoordinator,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp; // so the lasttimeStamp is the most recent timestamp
        i_keyHash = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        s_raffleState = RaffleState.OPEN;
    }

    function enterRaffle() external payable {
        // require(msg.value >= i_entranceFee, "Not Enough ETH sent!");
        // checks
        if (msg.value < i_entranceFee) {
            revert Raffle__NotEnoughETHSent();
        }

        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }
        s_players.push(payable(msg.sender));
        // Why work with events?
        // 1. Making migrations easier
        // 2. Makes front end "indexing" easier
        emit RaffleEntered(msg.sender);
    }

    // Checkupkeep and PerformUpkeep is for automation
    // Checkupkeep function is doing: When should the winner be picked?
    /**
     * @dev This is the function the Chainlink nodes will call to see
     * if the lottery is ready to have a winner picked.
     * The following should be true in order for upkeepNeeded to be true:
     * 1. The time interval has passed between raffle runs
     * 2. The lottery is open
     * 3. The contract has ETH (has players/has people entered the raffle)
     * 4. Implicitly, your subscription has LINK
     * @param - ignored
     * @return upkeepNeeded - true if it's time to resatrt the lottery
     * @return - ignored
     */
    function checkUpkeep(
        // checkUpkeep function  which the chainlink nopdes will consistently call to make sure its time to call the lottery
        bytes memory /* checkData */
    ) public view returns (bool upkeepNeeded, bytes memory /* performData */) {
        // bool upkeepNeeded is saying if it's time to pick a winner or is it time to restart the lottery
        bool timeHasPassed = ((block.timestamp - s_lastTimeStamp) >=
            i_interval);
        bool isOpen = s_raffleState == RaffleState.OPEN;
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = timeHasPassed && isOpen && hasBalance && hasPlayers;
        return (upkeepNeeded, "");
    }

    // We want pickWinner to
    // 1. Get a random number
    // 2. Use the random number to get the winner
    // 3. This things should be automatically called
    // What performUpkeep is doing: Hey! It's time to kickoff the VRF call we need the random number, please!
    // PerformUpkeep will pick the random winner, chainlink automation will call performUpkeep and performUpkeep will call chainlinkVRF, VRF will call fullfillRandomWords and thats how we will get the winner
    function performUpkeep(bytes calldata /* performData */) external {
        // 1. But first we want to check if enough time has passed we can do that using block.timestamp
        // checks
        (bool upkeepNeeded, ) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }

        s_raffleState = RaffleState.CALCULATING; // Once someone kickoff VRF req we are in a calculating state (Not Open)
        // So if enough time has already passed then we will get a random number
        // Get random number using chainlink 2.5
        // 1. Request RNG
        // 2. Chainlink oracle will give us the RNG
        VRFV2PlusClient.RandomWordsRequest memory request = VRFV2PlusClient
            .RandomWordsRequest({
                keyHash: i_keyHash, // some gas price to work with chainlink node
                subId: i_subscriptionId, // how we actually fund oracle gas for working with chainlink VRF
                requestConfirmations: REQUEST_CONFIRMATIONS, // how many blocks should we wait to verify
                callbackGasLimit: i_callbackGasLimit, // so that we don't accidentally use toom uch gas on the callback
                numWords: NUM_WORDS, // how many random number we wants
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // Set nativePayment to true to pay for VRF requests with Sepolia ETH instead of LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: false})
                )
            });
        uint256 requestId = s_vrfCoordinator.requestRandomWords(request); // request here is the struct (look above) [we are s_vrfCoordinator to call requestrandomwords by using the request struct]
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(
        uint256 /* requestId,*/,
        uint256[] calldata randomWords
    ) internal override {
        // 1. Get the winner
        // Effects
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_players = new address payable[](0); // Resetting the s_players array
        s_lastTimeStamp = block.timestamp; // Resetting the lastTimeStamp/clock
        s_raffleState = RaffleState.OPEN; // Since we already picked a winner we are now open
        emit WinnerPicked(s_recentWinner);
        // 2. Pay the winner
        // Interactions
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        if (!success) {
            revert Raffle__TransferFailed();
        }
    }

    /** Getter Functions */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getRafflePlayer(
        uint256 indexOfPlayer
    ) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }
}
