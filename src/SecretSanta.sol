// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SecretSanta
 * @notice Privacy-preserving Secret Santa contract using BITE V2 threshold encryption
 * @dev Participants register encrypted wishlists, then reveal after assignment
 */
contract SecretSanta {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice Registration deadline timestamp
    uint256 public registrationDeadline;

    /// @notice Random seed for assignment
    uint256 public assignmentSeed;

    /// @notice Whether assignment has been completed
    bool public assignmentComplete;

    /// @notice Total number of participants
    uint256 public participantCount;

    // ============================================
    // STRUCTS
    // ============================================

    /// @notice Participant information
    struct Participant {
        address addr;                  // Participant address
        bytes encryptedWishlist;       // BITE encrypted (address shippingAddress, string wishlist)
        bool registered;               // Registration status
    }

    /// @notice Decryption request information
    struct DecryptionRequest {
        address requester;             // Santa requesting decryption
        uint256 recipientIndex;        // Index of recipient in participantList
        bool fulfilled;                // Whether decryption was completed
    }

    // ============================================
    // MAPPINGS
    // ============================================

    /// @notice Mapping from address to participant data
    mapping(address => Participant) public participants;

    /// @notice List of all participant addresses
    address[] public participantList;

    /// @notice Mapping from Santa to their assigned Recipient
    mapping(address => address) public santaToRecipient;

    /// @notice Mapping from Santa to their decrypted recipient wishlist
    mapping(address => bytes) public recipientWishlists;

    /// @notice Decryption requests by index
    mapping(uint256 => DecryptionRequest) public decryptionRequests;

    /// @notice Total number of decryption requests
    uint256 public decryptionCount;

    // ============================================
    // EVENTS
    // ============================================

    event Registered(address indexed participant, uint256 totalParticipants);
    event AssignmentComplete(uint256 seed, uint256 totalAssignments);
    event DecryptionRequested(address indexed requester, address indexed recipient, uint256 requestId);
    event WishlistRevealed(address indexed santa, address indexed recipient);

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize the Secret Santa contract
     * @param _durationSeconds Registration period duration in seconds
     */
    constructor(uint256 _durationSeconds) {
        registrationDeadline = block.timestamp + _durationSeconds;
    }

    // ============================================
    // REGISTRATION
    // ============================================

    /**
     * @notice Register as a participant with encrypted wishlist
     * @dev Client should encrypt: abi.encode(address shippingAddress, string wishlistItems)
     * @param _encryptedWishlist BITE encrypted wishlist data
     */
    function register(bytes memory _encryptedWishlist) external {
        require(block.timestamp < registrationDeadline, "Registration closed");
        require(!participants[msg.sender].registered, "Already registered");

        participantCount++;
        participants[msg.sender] = Participant({
            addr: msg.sender,
            encryptedWishlist: _encryptedWishlist,
            registered: true
        });
        participantList.push(msg.sender);

        emit Registered(msg.sender, participantCount);
    }

    // ============================================
    // ASSIGNMENT
    // ============================================

    /**
     * @notice Trigger the Secret Santa assignment
     * @dev Uses Fisher-Yates shuffle with self-assignment prevention
     */
    function triggerAssignment() external {
        require(block.timestamp >= registrationDeadline, "Registration still open");
        require(!assignmentComplete, "Assignment already complete");
        require(participantCount >= 2, "Not enough participants");

        // Generate seed from block properties for pseudo-randomness
        assignmentSeed = uint256(keccak256(
            abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                msg.sender,
                participantCount
            )
        ));

        _performDerangement();

        assignmentComplete = true;

        emit AssignmentComplete(assignmentSeed, participantCount);
    }

    /**
     * @notice Perform Fisher-Yates derangement (no self-assignments)
     * @dev Internal function implementing the assignment algorithm
     */
    function _performDerangement() internal {
        uint256 n = participantCount;

        // Start with identity mapping
        for (uint256 i = 0; i < n; i++) {
            santaToRecipient[participantList[i]] = participantList[i];
        }

        // Fisher-Yates shuffle with self-assignment prevention
        uint256 seed = assignmentSeed;

        for (uint256 i = n - 1; i > 0; i--) {
            // Generate pseudo-random index
            seed = uint256(keccak256(abi.encodePacked(seed, i)));
            uint256 j = seed % (i + 1);

            // Swap recipients
            address temp = santaToRecipient[participantList[i]];
            santaToRecipient[participantList[i]] = santaToRecipient[participantList[j]];
            santaToRecipient[participantList[j]] = temp;

            // Prevent self-assignment
            if (santaToRecipient[participantList[i]] == participantList[i]) {
                // Swap with next person (wrap around if needed)
                uint256 nextIndex = (i + 1) % n;
                temp = santaToRecipient[participantList[i]];
                santaToRecipient[participantList[i]] = santaToRecipient[participantList[nextIndex]];
                santaToRecipient[participantList[nextIndex]] = temp;
            }
        }

        // Final check - ensure no self-assignments remain
        for (uint256 i = 0; i < n; i++) {
            if (santaToRecipient[participantList[i]] == participantList[i]) {
                // Find someone to swap with
                uint256 swapIndex = (i + 1) % n;
                address temp = santaToRecipient[participantList[i]];
                santaToRecipient[participantList[i]] = santaToRecipient[participantList[swapIndex]];
                santaToRecipient[participantList[swapIndex]] = temp;
            }
        }
    }

    // ============================================
    // DECRYPTION
    // ============================================

    /**
     * @notice Request to decrypt your recipient's wishlist
     * @dev Queues the request for batch processing via decryptAndExecute
     */
    function requestMyRecipient() external {
        require(participants[msg.sender].registered, "Not registered");
        require(assignmentComplete, "Assignment not complete");

        address recipient = santaToRecipient[msg.sender];
        require(recipient != address(0), "No recipient assigned");
        require(recipientWishlists[msg.sender].length == 0, "Already revealed");

        // Find recipient's index in participant list
        uint256 recipientIndex;
        for (uint256 i = 0; i < participantList.length; i++) {
            if (participantList[i] == recipient) {
                recipientIndex = i;
                break;
            }
        }

        decryptionCount++;
        decryptionRequests[decryptionCount] = DecryptionRequest({
            requester: msg.sender,
            recipientIndex: recipientIndex,
            fulfilled: false
        });

        emit DecryptionRequested(msg.sender, recipient, decryptionCount);
    }

    /**
     * @notice Trigger BITE decryption for all pending requests
     * @dev Calls BITE precompile at 0x1b to decrypt encrypted wishlists
     * @return count Number of decryption requests to process
     */
    function decryptAndExecute() external returns (uint256 count) {
        // Collect encrypted wishlists to decrypt
        bytes[] memory encryptedToDecrypt = new bytes[](decryptionCount);
        for (uint256 i = 0; i < decryptionCount; i++) {
            DecryptionRequest storage req = decryptionRequests[i + 1];
            if (!req.fulfilled && req.requester != address(0)) {
                address recipient = participantList[req.recipientIndex];
                encryptedToDecrypt[i] = participants[recipient].encryptedWishlist;
            }
        }

        // Generate random gas limit for BITE precompile
        uint256 randomGas = uint256(keccak256(abi.encodePacked(block.timestamp, block.number))) % 2500000 + 1000000;

        // Encode input for BITE precompile (0x1b)
        bytes memory input = abi.encode(randomGas, encryptedToDecrypt);

        // Call BITE precompile - this will trigger onDecrypt in the next block
        (bool success, bytes memory result) = address(0x1b).staticcall(input);
        require(success, "BITE precompile call failed");

        count = decryptionCount;
    }

    /**
     * @notice BITE V2 callback - receives decrypted wishlist data
     * @dev Called by SKALE network after decryptAndExecute
     * @param decryptedArguments Array of decrypted wishlist data
     * @param plaintextArguments Array of plaintext arguments (unused)
     */
    function onDecrypt(
        bytes[] memory decryptedArguments,
        bytes[] memory plaintextArguments
    ) external {

        // Process each decrypted wishlist
        for (uint256 i = 0; i < decryptedArguments.length; i++) {
            uint256 requestId = i + 1;

            if (requestId <= decryptionCount) {
                DecryptionRequest storage request = decryptionRequests[requestId];

                if (!request.fulfilled && request.requester != address(0)) {
                    // Store the decrypted wishlist for the requester
                    recipientWishlists[request.requester] = decryptedArguments[i];
                    request.fulfilled = true;

                    address recipient = participantList[request.recipientIndex];
                    emit WishlistRevealed(request.requester, recipient);
                }
            }
        }

        // Handle plaintext arguments if any (for testing)
        for (uint256 i = 0; i < plaintextArguments.length; i++) {
            uint256 requestId = uint256(decryptedArguments.length) + i + 1;

            if (requestId <= decryptionCount) {
                DecryptionRequest storage request = decryptionRequests[requestId];

                if (!request.fulfilled && request.requester != address(0)) {
                    recipientWishlists[request.requester] = plaintextArguments[i];
                    request.fulfilled = true;

                    address recipient = participantList[request.recipientIndex];
                    emit WishlistRevealed(request.requester, recipient);
                }
            }
        }
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get your recipient's decrypted wishlist
     * @dev Access controlled - only the Santa can view their recipient's wishlist
     * @param _santa The address of the Santa
     * @return The decrypted wishlist data
     */
    function getMyRecipientWishlist(address _santa) external view returns (bytes memory) {
        // Only the Santa themselves can call this
        require(msg.sender == _santa, "Access denied");
        return recipientWishlists[_santa];
    }

    /**
     * @notice Get your assigned recipient address
     * @param _santa The address of the Santa
     * @return The address of the assigned recipient
     */
    function getMyRecipient(address _santa) external view returns (address) {
        require(participants[_santa].registered, "Not registered");
        require(assignmentComplete, "Assignment not complete");
        return santaToRecipient[_santa];
    }

    /**
     * @notice Check if an address is registered
     * @param _participant The address to check
     * @return True if registered
     */
    function isRegistered(address _participant) external view returns (bool) {
        return participants[_participant].registered;
    }

    /**
     * @notice Get all participant addresses
     * @return Array of participant addresses
     */
    function getAllParticipants() external view returns (address[] memory) {
        return participantList;
    }

    /**
     * @notice Get time remaining for registration
     * @return Seconds remaining (0 if closed)
     */
    function getRegistrationTimeRemaining() external view returns (uint256) {
        if (block.timestamp >= registrationDeadline) {
            return 0;
        }
        return registrationDeadline - block.timestamp;
    }

    /**
     * @notice Check if a Santa has revealed their recipient
     * @param _santa The Santa address
     * @return True if revealed
     */
    function hasRevealed(address _santa) external view returns (bool) {
        return recipientWishlists[_santa].length > 0;
    }
}
