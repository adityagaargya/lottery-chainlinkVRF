// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract Lottery is VRFConsumerBaseV2, ConfirmedOwner {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    uint256 public lobbyCount;

    struct Lobby {
        uint256 id;
        uint256 minDepositAmount;
        uint256 maxDepositAmount;
        uint256 ticketPrice;
        uint256 currentBalance;
        uint256 minParticipants;
        uint256 maxParticipants;
        uint256 currentParticipants;
        address[] participants;
        uint256 duration;
        uint256 createdAt;
        uint256 endsAt;
    }
    mapping(uint256 => Lobby) lobbyId;

    event LobbyCreated(
        uint256 indexed id,
        uint256 indexed ticketPrice,
        uint256 indexed duration,
        uint256 created
    );

    event EnterLobby(
        uint256 indexed id,
        address indexed participant,
        uint256 indexed currentParticipants,
        uint256 currentBalance,
        uint256 enteredTime
    );

    string public lastReturnedFortune;

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }

    /* requestId --> requestStatus */
    mapping(uint256 => RequestStatus) public s_requests;
    VRFCoordinatorV2Interface COORDINATOR;

    // Your VRF subscription ID.
    uint64 s_subscriptionId;

    // past requests Id.
    uint256[] public requestIds;
    uint256 public lastRequestId;

    bytes32 keyHash =
        0x354d2f95da55398f44b7cff77da56283d9c6c829a4bdf1bbcaf2ad6a4d081f61;

    uint32 callbackGasLimit = 100000;

    // The default is 3, but we set to 1 for faster dev.
    uint16 requestConfirmations = 1;

    // For this example, retrieve 1 random value per request.
    // Cannot exceed VRFCoordinatorV2.MAX_NUM_WORDS.
    uint32 numWords = 1;

    constructor(
        uint64 subscriptionId,
        address VRFCoordinator
    ) VRFConsumerBaseV2(VRFCoordinator) ConfirmedOwner(msg.sender) {
        lobbyCount = 0;
        COORDINATOR = VRFCoordinatorV2Interface(VRFCoordinator);
        s_subscriptionId = subscriptionId;
    }

    function createLobby(
        uint256 _minDepositAmount,
        uint256 _maxDepositAmount,
        uint256 _ticketPrice,
        uint256 _minParticipants,
        uint256 _maxParticipants,
        uint256 _duration
    ) public onlyOwner returns (uint256) {
        lobbyCount++;
        Lobby storage newLobby = lobbyId[lobbyCount];
        newLobby.id = lobbyCount;
        newLobby.minDepositAmount = _minDepositAmount;
        newLobby.maxDepositAmount = _maxDepositAmount;
        newLobby.ticketPrice = _ticketPrice;
        newLobby.minParticipants = _minParticipants;
        newLobby.maxParticipants = _maxParticipants;
        uint256 durationInSeconds = _duration * 1 days;
        newLobby.duration = durationInSeconds;
        newLobby.endsAt = durationInSeconds + block.timestamp;
        newLobby.createdAt = block.timestamp;

        emit LobbyCreated(
            newLobby.id,
            newLobby.ticketPrice,
            newLobby.duration,
            newLobby.createdAt
        );

        return newLobby.id;
    }

    function enterLobby(uint256 _lobbyId) public payable returns (address) {
        require(
            lobbyId[_lobbyId].currentBalance + msg.value <=
                lobbyId[_lobbyId].maxDepositAmount,
            "Lobby is full"
        );
        require(
            lobbyId[_lobbyId].currentParticipants + 1 <=
                lobbyId[_lobbyId].maxParticipants,
            "Lobby is full"
        );
        require(
            msg.value == lobbyId[_lobbyId].ticketPrice,
            "Recieved amount is not equal to lobby ticket price"
        );
        lobbyId[_lobbyId].participants.push(msg.sender);
        lobbyId[_lobbyId].currentBalance += lobbyId[_lobbyId].ticketPrice;
        lobbyId[_lobbyId].currentParticipants += 1;
        return msg.sender;
    }

    function getLobbyMaxAllowedParticipants(
        uint256 _lobbyId
    ) public view returns (uint256) {
        return lobbyId[_lobbyId].maxParticipants;
    }

    function getLobbyMaxAllowedDeposit(
        uint256 _lobbyId
    ) public view returns (uint256) {
        return lobbyId[_lobbyId].maxDepositAmount;
    }

    function getLobbyCurrentSize(
        uint256 _lobbyId
    ) public view returns (uint256) {
        return lobbyId[_lobbyId].currentParticipants;
    }

    function getLobbyCurrentBalance(
        uint256 _lobbyId
    ) public view returns (uint256) {
        return lobbyId[_lobbyId].currentBalance;
    }

    function remainingTimeOfLobby(
        uint256 _lobbyId
    ) public view returns (uint256) {
        return block.timestamp - lobbyId[_lobbyId].endsAt;
    }

    function withdrawBalance() internal onlyOwner {
        (bool sent, ) = msg.sender.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether in withdraw");
    }

    function requestRandomWords()
        external
        onlyOwner
        returns (uint256 requestId)
    {
        // Will revert if subscription is not set and funded.
        requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] memory _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }

    function getContractBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getWinner(uint256 _lobbyId) public view returns (address) {
        uint256 randomIndex = s_requests[lastRequestId].randomWords[0] %
            lobbyId[_lobbyId].participants.length;

        // lastReturnedFortune = winner;
        return lobbyId[_lobbyId].participants[randomIndex];
    }
}
