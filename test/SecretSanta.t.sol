// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SecretSanta.sol";

/**
 * @title SecretSantaTest
 * @notice Test suite for SecretSanta contract
 */
contract SecretSantaTest is Test {
    SecretSanta public secretSanta;
    uint256 public registrationDuration = 1 weeks;
    uint256 public registrationDeadline;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC4A11E);
    address public diana = address(0xD14A4);

    event Registered(address indexed participant, uint256 totalParticipants);
    event AssignmentComplete(uint256 seed, uint256 totalAssignments);
    event DecryptionRequested(address indexed requester, address indexed recipient, uint256 requestId);
    event WishlistRevealed(address indexed santa, address indexed recipient);

    function setUp() public {
        secretSanta = new SecretSanta(registrationDuration);
        registrationDeadline = block.timestamp + registrationDuration;
    }

    // ============================================
    // CONSTRUCTOR TESTS
    // ============================================

    function test_ConstructorSetsDeadline() public view {
        assertEq(secretSanta.registrationDeadline(), registrationDeadline);
    }

    function test_ConstructorZeroDuration() public {
        SecretSanta zeroDuration = new SecretSanta(0);
        assertEq(zeroDuration.registrationDeadline(), block.timestamp);
    }

    // ============================================
    // REGISTRATION TESTS
    // ============================================

    function test_RegisterSuccess() public {
        bytes memory encryptedWishlist = hex"1234";

        vm.expectEmit(true, true, false, true);
        emit Registered(alice, 1);

        vm.prank(alice);
        secretSanta.register(encryptedWishlist);

        assertEq(secretSanta.participantCount(), 1);
        assertTrue(secretSanta.isRegistered(alice));
    }

    function test_RegisterMultipleParticipants() public {
        bytes memory encryptedWishlist = hex"1234";

        vm.prank(alice);
        secretSanta.register(encryptedWishlist);

        vm.prank(bob);
        secretSanta.register(encryptedWishlist);

        vm.prank(charlie);
        secretSanta.register(encryptedWishlist);

        assertEq(secretSanta.participantCount(), 3);
        assertTrue(secretSanta.isRegistered(alice));
        assertTrue(secretSanta.isRegistered(bob));
        assertTrue(secretSanta.isRegistered(charlie));
    }

    function test_RegisterFailsAfterDeadline() public {
        vm.warp(registrationDeadline + 1);

        vm.prank(alice);
        vm.expectRevert("Registration closed");
        secretSanta.register(hex"1234");
    }

    function test_RegisterFailsIfAlreadyRegistered() public {
        vm.prank(alice);
        secretSanta.register(hex"1234");

        vm.prank(alice);
        vm.expectRevert("Already registered");
        secretSanta.register(hex"5678");
    }

    function test_GetAllParticipants() public {
        vm.prank(alice);
        secretSanta.register(hex"1234");

        vm.prank(bob);
        secretSanta.register(hex"5678");

        address[] memory participants = secretSanta.getAllParticipants();
        assertEq(participants.length, 2);
        assertEq(participants[0], alice);
        assertEq(participants[1], bob);
    }

    function test_GetRegistrationTimeRemaining() public {
        uint256 remaining = secretSanta.getRegistrationTimeRemaining();
        assertApproxEqAbs(remaining, registrationDuration, 1 seconds);

        vm.warp(registrationDeadline - 100);
        assertEq(secretSanta.getRegistrationTimeRemaining(), 100);

        vm.warp(registrationDeadline + 1);
        assertEq(secretSanta.getRegistrationTimeRemaining(), 0);
    }

    // ============================================
    // ASSIGNMENT TESTS
    // ============================================

    function test_TriggerAssignmentSuccess() public {
        _registerParticipants(4);
        vm.warp(registrationDeadline + 1);

        vm.expectEmit(false, false, false, true);
        emit AssignmentComplete(0, 4); // Seed is unpredictable

        secretSanta.triggerAssignment();

        assertTrue(secretSanta.assignmentComplete());
    }

    function test_TriggerAssignmentFailsBeforeDeadline() public {
        _registerParticipants(2);

        vm.expectRevert("Registration still open");
        secretSanta.triggerAssignment();
    }

    function test_TriggerAssignmentFailsIfAlreadyComplete() public {
        _registerParticipants(2);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        vm.expectRevert("Assignment already complete");
        secretSanta.triggerAssignment();
    }

    function test_TriggerAssignmentFailsWithNotEnoughParticipants() public {
        vm.prank(alice);
        secretSanta.register(hex"1234");
        vm.warp(registrationDeadline + 1);

        vm.expectRevert("Not enough participants");
        secretSanta.triggerAssignment();
    }

    function test_NoSelfAssignment() public {
        _registerParticipants(5);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        // Check that no one is assigned to themselves
        address[] memory participants = secretSanta.getAllParticipants();
        for (uint256 i = 0; i < participants.length; i++) {
            address recipient = secretSanta.getMyRecipient(participants[i]);
            assertNotEq(recipient, participants[i], "Self-assignment detected");
        }
    }

    function test_EveryoneGetsRecipient() public {
        _registerParticipants(4);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        address[] memory participants = secretSanta.getAllParticipants();
        address[] memory recipients = new address[](participants.length);

        // Collect all recipients
        for (uint256 i = 0; i < participants.length; i++) {
            recipients[i] = secretSanta.getMyRecipient(participants[i]);
            assertNotEq(recipients[i], address(0), "Zero address recipient");
        }

        // Check that everyone has a unique recipient
        for (uint256 i = 0; i < recipients.length; i++) {
            for (uint256 j = i + 1; j < recipients.length; j++) {
                assertNotEq(recipients[i], recipients[j], "Duplicate recipient");
            }
        }
    }

    function test_GetMyRecipientFailsBeforeAssignment() public {
        vm.prank(alice);
        secretSanta.register(hex"1234");

        vm.expectRevert("Assignment not complete");
        secretSanta.getMyRecipient(alice);
    }

    function test_GetMyRecipientFailsIfNotRegistered() public {
        _registerParticipants(2);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        vm.expectRevert("Not registered");
        secretSanta.getMyRecipient(diana);
    }

    // ============================================
    // DECRYPTION TESTS
    // ============================================

    function test_RequestMyRecipientSuccess() public {
        _registerParticipants(3);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        address recipient = secretSanta.getMyRecipient(alice);

        vm.expectEmit(true, true, false, true);
        emit DecryptionRequested(alice, recipient, 1);

        vm.prank(alice);
        secretSanta.requestMyRecipient();

        assertEq(secretSanta.decryptionCount(), 1);
        (address requester, uint256 recipientIndex, bool fulfilled) = secretSanta.decryptionRequests(1);
        assertEq(requester, alice);
        assertEq(fulfilled, false);
    }

    function test_RequestMyRecipientFailsIfNotRegistered() public {
        _registerParticipants(2);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        vm.prank(diana);
        vm.expectRevert("Not registered");
        secretSanta.requestMyRecipient();
    }

    function test_RequestMyRecipientFailsBeforeAssignment() public {
        vm.prank(alice);
        secretSanta.register(hex"1234");

        vm.prank(alice);
        vm.expectRevert("Assignment not complete");
        secretSanta.requestMyRecipient();
    }

    function test_RequestMyRecipientFailsIfAlreadyRevealed() public {
        _registerParticipants(2);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        vm.prank(alice);
        secretSanta.requestMyRecipient();

        // Mock decryption by directly setting the wishlist
        vm.store(
            address(secretSanta),
            keccak256(abi.encode(alice, 7)), // Slot 7 is recipientWishlists mapping
            bytes32(uint256(1))
        );

        vm.prank(alice);
        vm.expectRevert("Already revealed");
        secretSanta.requestMyRecipient();
    }

    // ============================================
    // onDecrypt TESTS
    // ============================================

    function test_OnDecryptStoresWishlists() public {
        _registerParticipants(3);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        vm.prank(alice);
        secretSanta.requestMyRecipient();

        vm.prank(bob);
        secretSanta.requestMyRecipient();

        // Prepare mock decrypted data
        bytes[] memory decryptedArgs = new bytes[](2);
        decryptedArgs[0] = abi.encode(address(0x1234), "Alice's wishlist");
        decryptedArgs[1] = abi.encode(address(0x5678), "Bob's wishlist");

        bytes[] memory plaintextArgs = new bytes[](0);

        // Mock SKALE system address
        vm.prank(address(0xFFff0000000000000000000000000000000000ff));
        secretSanta.onDecrypt(decryptedArgs, plaintextArgs);

        // Check that wishlists were stored
        assertEq(secretSanta.recipientWishlists(alice), decryptedArgs[0]);
        assertEq(secretSanta.recipientWishlists(bob), decryptedArgs[1]);
        assertTrue(secretSanta.hasRevealed(alice));
        assertTrue(secretSanta.hasRevealed(bob));
    }

    // ============================================
    // VIEW FUNCTION TESTS
    // ============================================

    function test_GetMyRecipientWishlistAccessControl() public {
        _registerParticipants(2);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        // Mock a decrypted wishlist
        bytes memory mockWishlist = abi.encode(address(0x1234), "Test wishlist");
        vm.store(
            address(secretSanta),
            keccak256(abi.encode(alice, 7)),
            bytes32(uint256(1))
        );

        vm.prank(alice);
        vm.expectRevert("Access denied");
        secretSanta.getMyRecipientWishlist(bob);
    }

    function test_HasRevealed() public {
        _registerParticipants(2);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        assertFalse(secretSanta.hasRevealed(alice));

        // Mock decryption
        vm.store(
            address(secretSanta),
            keccak256(abi.encode(alice, 7)),
            bytes32(uint256(1))
        );

        assertTrue(secretSanta.hasRevealed(alice));
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _registerParticipants(uint256 count) internal {
        address[4] memory participants = [alice, bob, charlie, diana];

        for (uint256 i = 0; i < count; i++) {
            bytes memory encryptedWishlist = abi.encode(i);
            vm.prank(participants[i]);
            secretSanta.register(encryptedWishlist);
        }
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_RegisterManyParticipants(uint8 count) public {
        vm.assume(count >= 2 && count <= 100);
        vm.warp(registrationDeadline - 1);

        for (uint256 i = 0; i < count; i++) {
            address participant = address(uint160(i + 1));
            vm.prank(participant);
            secretSanta.register(abi.encode(i));
        }

        assertEq(secretSanta.participantCount(), count);

        vm.warp(registrationDeadline + 1);
        secretSanta.triggerAssignment();

        // Verify no self-assignments
        for (uint256 i = 0; i < count; i++) {
            address participant = address(uint160(i + 1));
            address recipient = secretSanta.getMyRecipient(participant);
            assertNotEq(recipient, participant);
        }
    }

    function testFuzz_RegistrationDuration(uint256 duration) public {
        vm.assume(duration > 0 && duration < 365 days);

        SecretSanta customSanta = new SecretSanta(duration);

        assertEq(customSanta.registrationDeadline(), block.timestamp + duration);
    }

    // ============================================
    // INvariant TESTS
    // ============================================

    function testInvariant_NoSelfAssignmentAfterAssignment() public {
        _registerParticipants(4);
        vm.warp(registrationDeadline + 1);

        secretSanta.triggerAssignment();

        address[] memory participants = secretSanta.getAllParticipants();
        for (uint256 i = 0; i < participants.length; i++) {
            address recipient = secretSanta.getMyRecipient(participants[i]);
            assertNotEq(recipient, participants[i]);
        }
    }
}
