# SecretSanta Smart Contract

## Contract Overview

The `SecretSanta.sol` contract implements a privacy-preserving Secret Santa gift exchange using BITE V2 threshold encryption on the SKALE network.

## Architecture

### State Variables

| Variable | Type | Description |
|----------|------|-------------|
| `registrationDeadline` | `uint256` | Timestamp when registration closes |
| `assignmentSeed` | `uint256` | Random seed used for derangement |
| `assignmentComplete` | `bool` | Whether assignment has been executed |
| `participantCount` | `uint256` | Total number of registered participants |

### Structs

**Participant**:
```solidity
struct Participant {
    address addr;                  // Participant address
    bytes encryptedWishlist;       // BITE encrypted (address shippingAddress, string wishlist)
    bool registered;               // Registration status
}
```

**DecryptionRequest**:
```solidity
struct DecryptionRequest {
    address requester;             // Santa requesting decryption
    uint256 recipientIndex;        // Index of recipient in participantList
    bool fulfilled;                // Whether decryption was completed
}
```

### Mappings

| Mapping | Key | Value | Description |
|---------|-----|-------|-------------|
| `participants` | `address` | `Participant` | Participant data by address |
| `santaToRecipient` | `address` | `address` | Santa => Recipient assignment |
| `recipientWishlists` | `address` | `bytes` | Decrypted wishlist for Santa |
| `decryptionRequests` | `uint256` | `DecryptionRequest` | Pending decryption requests |

### Arrays

| Variable | Type | Description |
|----------|------|-------------|
| `participantList` | `address[]` | Ordered list of all participants |

## Functions

### Constructor

```solidity
constructor(uint256 _durationSeconds)
```
- Sets `registrationDeadline = block.timestamp + _durationSeconds`
- Default: 1 week (604800 seconds)

### Registration

```solidity
function register(bytes memory _encryptedWishlist) external
```
- **Requirements**: Registration open, not already registered
- **Client-side**: Encrypt `abi.encode(address shippingAddress, string wishlistItems)` using BITE
- **Gas**: 500,000 recommended

### Assignment

```solidity
function triggerAssignment() external
```
- **Requirements**: Registration closed, not complete, >= 2 participants
- **Algorithm**: Fisher-Yates shuffle with self-assignment prevention
- **Gas**: 1,000,000 recommended

```solidity
function _performDerangement() internal
```
- Implements derangement ensuring `santaToRecipient[santa] != santa`
- Uses pseudo-random seed from block properties

### Decryption

```solidity
function requestMyRecipient() external
```
- **Requirements**: Registered, assignment complete, not yet revealed
- Creates decryption request with recipient index

```solidity
function decryptAndExecute() external returns (uint256 count)
```
- Returns `decryptionCount` for SKALE to process
- Triggers `onDecrypt()` callback in next block
- **Gas**: 5,000,000 recommended

```solidity
function onDecrypt(bytes[] memory decryptedArguments, bytes[] memory plaintextArguments) external
```
- **Access Control**: Only `SKALE_SYSTEM` address
- Stores decrypted wishlists for each requester
- Emits `WishlistRevealed` event

### View Functions

```solidity
function getMyRecipientWishlist(address _santa) external view returns (bytes memory)
```
- Access controlled: `msg.sender == _santa`
- Returns decrypted wishlist data

```solidity
function getMyRecipient(address _santa) external view returns (address)
```
- Returns assigned recipient address

```solidity
function isRegistered(address _participant) external view returns (bool)
```

```solidity
function getAllParticipants() external view returns (address[] memory)
```

```solidity
function getRegistrationTimeRemaining() external view returns (uint256)
```

```solidity
function hasRevealed(address _santa) external view returns (bool)
```

## Events

```solidity
event Registered(address indexed participant, uint256 totalParticipants);
event AssignmentComplete(uint256 seed, uint256 totalAssignments);
event DecryptionRequested(address indexed requester, address indexed recipient, uint256 requestId);
event WishlistRevealed(address indexed santa, address indexed recipient);
```

## BITE V2 Integration

### BITE V2 Precompile Addresses

BITE V2 uses precompile addresses for threshold encryption operations:

| Precompile | Address | Purpose |
|------------|---------|---------|
| `SUBMIT_CTX` | `0x14` | Submit Conditional Transaction (CTX) |
| Direct decrypt | `0x1b` | Direct decryption (simpler pattern) |

**Note**: Secret Santa uses the `0x1b` pattern for simple decryption. For CTX (conditional execution), use `0x14` with the `BITEPrecompile` library pattern.

### Contract-Level BITE V2 Pattern

**Important**: BITE V2 does NOT require special constants in your contract. The encryption is handled entirely client-side.

```solidity
// ❌ NOT NEEDED in contract:
// address constant BITE_MAGIC = 0x...;
// address constant SKALE_SYSTEM = 0x...;

// ✅ Just store encrypted bytes:
mapping(address => bytes) public encryptedData;
```

### `onDecrypt` Callback

The `onDecrypt` callback is called by SKALE after decryption. **No access control needed** - SKALE manages this internally.

```solidity
function onDecrypt(
    bytes[] calldata decryptedArguments,  // Decrypted values
    bytes[] calldata plaintextArguments   // Plaintext values (if any)
) external {
    // Process decrypted data
    for (uint256 i = 0; i < decryptedArguments.length; i++) {
        // Handle each decrypted value
    }
}
```

### `decryptAndExecute` Pattern

For simple decryption (like Secret Santa), call the `0x1b` precompile:

```solidity
function decryptAndExecute() external returns (uint256) {
    // Collect encrypted data to decrypt
    bytes[] memory encryptedToDecrypt = new bytes[](count);
    for (uint256 i = 0; i < count; i++) {
        encryptedToDecrypt[i] = /* encrypted data */;
    }

    // Generate random gas limit
    uint256 randomGas = uint256(keccak256(abi.encodePacked(
        block.timestamp, block.number
    ))) % 2500000 + 1000000;

    // Encode input: abi.encode(randomGas, abi.encode(encryptedArgs, plaintextArgs))
    bytes memory input = abi.encode(randomGas, encryptedToDecrypt);

    // Call BITE precompile at 0x1b
    (bool success, bytes memory result) = address(0x1b).staticcall(input);
    require(success, "BITE precompile call failed");

    return count;
}
```

### Client-Side Encryption Pattern

```typescript
// Encode wishlist data
const data = encodeAbiParameters(
  [
    { name: 'shippingAddress', type: 'address' },
    { name: 'wishlist', type: 'string' }
  ],
  [shippingAddress, wishlistItems]
);

// Encrypt with BITE
const bite = new BITE(skaleEndpoint);
const encrypted = await bite.encryptMessage(data);

// Register on contract
const { request } = await publicClient.simulateContract({
  address: contractAddress,
  abi: SecretSantaABI,
  functionName: 'register',
  args: [encrypted],
  account: address
});

const hash = await walletClient.writeContract(request);
```

### Decryption Flow

1. User calls `requestMyRecipient()` - queues decryption request
2. Anyone calls `decryptAndExecute()` - triggers BITE precompile
3. SKALE network decrypts and calls `onDecrypt()` in next block
4. Santa calls `getMyRecipientWishlist(address)` to view result

### Key Differences: `0x1b` vs `0x14` Precompile

| Feature | `0x1b` (Direct) | `0x14` (CTX) |
|---------|-----------------|---------------|
| Purpose | Simple decryption | Conditional execution |
| Returns | Nothing | `ctxSender` address to fund |
| Gas handling | Auto | Manual (must fund ctxSender) |
| Use case | Secret Santa, voting | Limit orders, AMM swaps |

## Gas Limits

| Operation | Gas Limit |
|-----------|-----------|
| `register()` | 500,000 |
| `triggerAssignment()` | 1,000,000 |
| `decryptAndExecute()` | 5,000,000 |
| General transactions | 300,000 |

## Deployment

```bash
# Compile
yarn compile

# Deploy to SKALE testnet
yarn deploy

# Verify (if explorer available)
npx hardhat verify --network skale <CONTRACT_ADDRESS> <REGISTRATION_DURATION>
```

## Testing Checklist

- [ ] Registration works before deadline
- [ ] Registration fails after deadline
- [ ] Duplicate registration fails
- [ ] Assignment produces valid derangement (no self-assignment)
- [ ] Each Santa gets unique recipient
- [ ] Decryption request only works after assignment
- [ ] Only requester can view their recipient's wishlist
- [ ] `onDecrypt` properly stores decrypted data
- [ ] Events emit correctly
