# Smart Will - Blockchain Estate Distribution

A professional Clarity smart contract for the Stacks blockchain that enables secure, time-locked digital wills with multi-beneficiary support.

## Overview

Smart Will allows users to create digital wills that automatically distribute STX tokens to designated beneficiaries based on predetermined block height conditions. The contract provides complete control over asset distribution with enterprise-grade security features.

## Project Structure

```
smart_will/
├── contracts/
│   └── smart_will.clar          # Main smart contract (669 lines)
├── tests/
│   └── smart_will.test.ts       # Comprehensive test suite (872 lines, 39 tests)
├── settings/
│   ├── Devnet.toml             # Development network config
│   ├── Testnet.toml            # Test network config
│   └── Mainnet.toml            # Production network config
├── Clarinet.toml               # Clarinet project configuration
├── package.json                # Node.js dependencies and scripts
├── tsconfig.json               # TypeScript configuration
└── vitest.config.js            # Test runner configuration
```

## Key Features

- **Multi-Beneficiary Support**: Distribute assets to up to 50 beneficiaries with individual allocations
- **Block Height Conditions**: Release assets automatically when specified block height is reached
- **Owner Controls**: Update beneficiaries and cancel wills before release conditions are met
- **Security First**: Comprehensive validation, double-claim prevention, and balance verification
- **Event Logging**: Complete audit trail for all major contract interactions
- **Professional Grade**: Type-safe implementation with detailed documentation and post-conditions

## Core Functions

### Public Functions
- `create-will(beneficiaries, allocations, release-block-height)` - Create a new will with beneficiaries and release conditions
- `update-beneficiary(beneficiary, new-allocation)` - Modify beneficiary allocations before release
- `cancel-will()` - Cancel will and withdraw all assets
- `claim(will-id)` - Beneficiaries claim their allocation after release condition

### Read-Only Functions
- `get-will-info(will-id)` - Get comprehensive will information
- `get-beneficiary-info(will-id, beneficiary)` - Get beneficiary allocation and claim status
- `get-owner-will-id(owner)` - Get will ID for an owner
- `is-release-condition-met(will-id)` - Check if release condition is met
- `can-claim(will-id, beneficiary)` - Check if beneficiary can claim
- `get-will-stats(will-id)` - Get detailed will statistics
- `get-contract-balance()` - Check contract's STX balance

## Security Features

- **Time-Lock Protection**: Prevents early claims before release block height
- **Double-Claim Prevention**: Tracks claim status to prevent duplicate claims
- **Balance Validation**: Validates allocations don't exceed locked amounts
- **Owner Authorization**: Comprehensive owner authorization checks
- **Contract Solvency**: Contract balance verification before transfers
- **Input Validation**: Extensive validation of all inputs and state transitions
- **Event Audit Trail**: Complete logging of all contract interactions

## Error Handling

The contract implements comprehensive error handling with 13 distinct error codes:
- Authorization errors (unauthorized access)
- Will state errors (not found, already exists, cancelled)
- Beneficiary errors (invalid, duplicate, allocation issues)
- Condition errors (release conditions, balance checks)

## Development & Testing

### Prerequisites
- Node.js and npm
- Clarinet CLI
- Stacks blockchain development environment

### Available Scripts
```bash
npm test              # Run unit tests
npm run test:report   # Run tests with coverage and cost analysis
npm run test:watch    # Watch mode for continuous testing
```

### Testing Framework
- **Vitest**: Modern test runner with TypeScript support
- **Clarinet SDK**: Stacks blockchain testing utilities
- **Coverage Analysis**: Built-in test coverage reporting
- **Cost Analysis**: Transaction cost estimation

### Test Suite

The Smart Will contract includes a comprehensive test suite with **39 passing tests** covering all contract functionality:

#### Test Coverage (100% Pass Rate)

**Will Creation Tests (7 tests)**
- ✅ Successful will creation with valid parameters
- ✅ Validation of release block height (must be in future)
- ✅ Beneficiary/allocation count matching
- ✅ Zero allocation detection
- ✅ Duplicate will prevention (one per owner)
- ✅ Insufficient balance handling
- ✅ Empty beneficiary list validation

**Will Update Tests (6 tests)**
- ✅ Increase beneficiary allocation
- ✅ Decrease beneficiary allocation
- ✅ Add new beneficiaries to existing will
- ✅ Authorization checks (owner-only updates)
- ✅ Zero allocation prevention
- ✅ Pre-release-only update enforcement

**Will Cancellation Tests (4 tests)**
- ✅ Successful cancellation with STX refund
- ✅ Authorization checks (owner-only cancellation)
- ✅ Double-cancellation prevention
- ✅ Non-existent will error handling

**Claim Tests (6 tests)**
- ✅ Successful claims after release block
- ✅ Pre-release claim prevention
- ✅ Double-claim prevention
- ✅ Non-beneficiary claim rejection
- ✅ Cancelled will claim rejection
- ✅ Multiple independent beneficiary claims

**Read-Only Function Tests (8 tests)**
- ✅ Will information retrieval (`get-will-info`)
- ✅ Beneficiary data queries (`get-beneficiary-info`)
- ✅ Owner-to-will-ID mapping (`get-owner-will-id`)
- ✅ Release condition checking (`is-release-condition-met`)
- ✅ Claim eligibility verification (`can-claim`)
- ✅ Will statistics (`get-will-stats`)
- ✅ Will counter tracking (`get-will-counter`)
- ✅ Contract balance queries (`get-contract-balance`)

**Event Logging Tests (4 tests)**
- ✅ Will creation event logging
- ✅ Will update event logging
- ✅ Will cancellation event logging
- ✅ Claim event logging

**Edge Cases & Complex Scenarios (3 tests)**
- ✅ Maximum beneficiary limit (50 beneficiaries)
- ✅ Partial claim tracking across multiple beneficiaries
- ✅ Complete lifecycle (create → update → claim)

#### Running Tests

```bash
# Navigate to project directory
cd smart_will

# Install dependencies
npm install

# Run all tests
npm test

# Expected output:
# Test Files  1 passed (1)
#      Tests  39 passed (39)
```

#### Test File Location
[smart_will/tests/smart_will.test.ts](smart_will/tests/smart_will.test.ts)

## Use Cases

- **Estate Planning**: Automated inheritance distribution
- **Token Vesting**: Time-locked token release schedules
- **Conditional Payments**: Asset releases based on block height
- **Trustless Escrow**: Multi-party asset management without intermediaries
- **Corporate Benefits**: Employee benefit distributions
- **DAO Treasury**: Automated treasury distributions

## Technical Specifications

- **Language**: Clarity v3
- **Blockchain**: Stacks
- **Max Beneficiaries**: 50 per will
- **Asset Type**: STX tokens
- **Release Mechanism**: Block height-based conditions
- **Storage**: On-chain data maps and variables

Built with professional standards for production deployment on Stacks mainnet.