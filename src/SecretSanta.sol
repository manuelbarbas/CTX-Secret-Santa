// SPDX-License-Identifier: MIT
pragma solidity >=0.8.27;

import { IBiteSupplicant } from "@skalenetwork/bite-solidity/interfaces/IBiteSupplicant.sol";
import { BITE, PublicKey } from "@skalenetwork/bite-solidity/BITE.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title SecretSanta
 * @notice Privacy-preserving Secret Santa contract using BITE V2 threshold encryption
 * @dev Participants register encrypted wishlists, then reveal after assignment with CTX automatic decryption
 */
contract SecretSanta is IBiteSupplicant, Ownable {
    using Address for address payable;

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

    /// @notice Testing mode flag
    bool public testingMode = false;

    // ============================================
    // CTX CONSTANTS
    // ============================================

    /// @notice Minimum callback gas required for CTX execution
    uint256 public minCallbackGas = 300_000;

    /// @notice Minimum gas payment required (0.06 CREDIT)
    uint256 public constant MIN_GAS_PAYMENT = 0.06 ether;

    // ============================================
    // ERRORS
    // ============================================

    error AccessDenied();
    error NotEnoughValueSentForGas();

    // ============================================
    // STRUCTS
    // ============================================

    /// @notice Participant information
    struct Participant {
        address addr;                  // Participant address
        bytes encryptedWishlist;       // BITE encrypted (address shippingAddress, string wishlist)
        bool registered;               // Registration status
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

    /// @notice Mapping to track CTX executors allowed to call onDecrypt
    mapping(address => bool) private _canCallOnDecrypt;

    // ============================================
    // EVENTS
    // ============================================

    event Registered(address indexed participant, uint256 totalParticipants);
    event AssignmentComplete(uint256 seed, uint256 totalAssignments);
    event DecryptionRequested(address indexed requester, address indexed recipient);
    event WishlistRevealed(address indexed santa, address indexed recipient);

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Initialize the Secret Santa contract
     * @param _durationSeconds Registration period duration in seconds
     */
    constructor(uint256 _durationSeconds) Ownable(msg.sender) {
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
     * @notice Request to decrypt your recipient's wishlist with CTX gas payment
     * @dev Submits CTX for immediate decryption - requires gas payment based on gasprice
     */
    function requestMyRecipient() external payable {
        require(participants[msg.sender].registered, "Not registered");
        require(assignmentComplete, "Assignment not complete");
        require(msg.value >= MIN_GAS_PAYMENT, "Insufficient CTX gas payment");

        address recipient = santaToRecipient[msg.sender];
        require(recipient != address(0), "No recipient assigned");
        require(recipientWishlists[msg.sender].length == 0, "Already revealed");

        // Prepare encrypted arguments for CTX
        bytes[] memory encryptedArgs = new bytes[](1);
        encryptedArgs[0] = participants[recipient].encryptedWishlist;

        // Prepare plaintext arguments to pass requester and recipient info
        bytes[] memory plaintextArgs = new bytes[](1);
        plaintextArgs[0] = abi.encode(msg.sender, recipient);

        // Calculate allowed gas from payment (gasprice is fixed on SKALE)
        uint256 allowedGas = msg.value / tx.gasprice;
        require(allowedGas > minCallbackGas, NotEnoughValueSentForGas());

        // Submit CTX - network will decrypt and call onDecrypt in next block
        address payable ctxSender = BITE.submitCTX(
            BITE.SUBMIT_CTX_ADDRESS,
            allowedGas,
            encryptedArgs,
            plaintextArgs
        );

        // Whitelist the CTX executor to call onDecrypt
        _canCallOnDecrypt[ctxSender] = true;

        // Transfer gas payment to CTX executor
        ctxSender.sendValue(msg.value);

        emit DecryptionRequested(msg.sender, recipient);
    }

    /**
     * @notice BITE V2 callback - receives decrypted wishlist data
     * @dev Called by SKALE network after CTX submission
     * @param decryptedArguments Array of decrypted wishlist data
     * @param plaintextArguments Array of plaintext arguments containing (requester, recipient)
     */
    function onDecrypt(
        bytes[] calldata decryptedArguments,
        bytes[] calldata plaintextArguments
    )
        external
        override
    {
        // Only the whitelisted CTX executor can call this
        require(_canCallOnDecrypt[msg.sender], AccessDenied());
        _canCallOnDecrypt[msg.sender] = false;

        // Process each decrypted wishlist
        for (uint256 i = 0; i < decryptedArguments.length; i++) {
            // Decode requester and recipient from plaintext arguments
            (address requester, address recipient) = abi.decode(
                plaintextArguments[i],
                (address, address)
            );

            // Ensure the requester hasn't already revealed
            if (recipientWishlists[requester].length == 0) {
                // Store the decrypted wishlist for the requester
                recipientWishlists[requester] = decryptedArguments[i];

                emit WishlistRevealed(requester, recipient);
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

    // ============================================
    // TESTING / ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Enable or disable testing mode
     * @dev Testing mode allows registration to remain open even after deadline
     * @param _enabled Whether to enable testing mode
     */
    function setTestingMode(bool _enabled) external onlyOwner {
        testingMode = _enabled;
    }

    /**
     * @notice Manually set assignment complete status (for testing)
     * @dev Only callable by owner when testing mode is enabled
     * @param _status Whether assignment is complete
     */
    function setAssignmentComplete(bool _status) external onlyOwner {
        require(testingMode, "Testing mode not enabled");
        assignmentComplete = _status;
    }

    /**
     * @notice Manually set registration deadline (for testing)
     * @dev Only callable by owner when testing mode is enabled
     * @param _newDeadline New registration deadline timestamp
     */
    function setRegistrationDeadline(uint256 _newDeadline) external onlyOwner {
        require(testingMode, "Testing mode not enabled");
        registrationDeadline = _newDeadline;
    }

    /**
     * @notice Manually trigger assignment with minimum participants (for testing)
     * @dev Only callable by owner when testing mode is enabled with only 1 participant
     */
    function emergencyAssignment() external onlyOwner {
        require(testingMode, "Testing mode not enabled");
        require(!assignmentComplete, "Assignment already complete");
        require(participantCount >= 1, "No participants");

        // Generate seed from block properties for pseudo-randomness
        assignmentSeed = uint256(keccak256(
            abi.encodePacked(
                block.timestamp,
                block.prevrandao,
                msg.sender,
                participantCount
            )
        ));

        // For testing with 1 participant, assign them to themselves
        if (participantCount == 1) {
            santaToRecipient[participantList[0]] = participantList[0];
        } else {
            _performDerangement();
        }

        assignmentComplete = true;

        emit AssignmentComplete(assignmentSeed, participantCount);
    }
}
