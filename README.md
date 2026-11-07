# Dynamic Bond Tokenization Platform

A blockchain-based prototype for tokenizing corporate bonds into fractional, KYC-controlled digital assets. The project combines a Solidity smart contract, a Python Flask API, and a browser-based dashboard to simulate issuance, transfer, coupon distribution, and maturity management for bond-backed tokens.

## Project Overview

This repository demonstrates how a traditional corporate bond can be represented as a digital token on Ethereum-compatible blockchain infrastructure.

In plain terms, the platform allows an issuer or custodian to:

- Create a bond as a tokenized asset
- Assign contract-level bond metadata such as ISIN, face value, coupon rate, and maturity
- Restrict participation to KYC-approved investors
- Distribute tokens to investors
- Allow transfers between verified wallet addresses
- Trigger coupon (interest) distribution
- Track claimable coupon amounts
- Mature the bond at the end of its lifecycle

The project is designed as a functional prototype and demo environment, not a full production-grade financial platform.

## Why This Project Exists

Traditional bond investing often involves:

- Complex onboarding and paperwork
- Manual custody records
- Slow settlement cycles
- Limited liquidity and fractional access
- Opaque investor participation records

This platform aims to show how smart contracts can bring transparency, automation, and programmability to bond issuance and servicing. It models a simplified version of a digital bond lifecycle on-chain.

## Core Features

### 1. Tokenized Bond Issuance
The system deploys a Solidity contract representing a corporate bond. The issuer provides metadata such as:

- bond name and symbol
- total token supply
-isin identifier
- face value
- coupon rate
- maturity period
- coupon frequency
- custodian and issuer wallet addresses

### 2. Investor KYC / Access Control
The smart contract contains allowlist and blacklist mappings.

- Only allowlisted addresses can transfer or receive tokens
- KYC IDs are stored against investor wallet addresses
- Blacklisted investors cannot participate

### 3. Coupon / Interest Management
The project includes logic for coupon distribution based on bond parameters.

- Coupons are calculated from the face value and rate
- Distribution is time-gated by the configured frequency
- Investors can check pending coupon amounts
- Investors can claim their due coupons

### 4. Transfer and Ownership Tracking
The token supports standard-like transfer behavior, including:

- balance checks
- transfers between verified addresses
- approvals and transfers via allowance

### 5. Lifecycle Management
The bond can be matured when the configured maturity date is reached.

- active vs matured state
- event emissions for lifecycle changes
- simplified principal settlement modeling

### 6. Demo UI and API
The project exposes a Python Flask API and a front-end dashboard that lets users:

- create a bond
- choose a bond from a registry
- whitelist investors
- check balances
- transfer tokens
- trigger coupon distribution
- mature the bond

## Architecture

The project follows a simple three-layer architecture:

### 1. Smart Contract Layer
Location: `BondSecurityToken.sol`

This is the core business logic of the platform. The contract handles:

- token issuance
- investor KYC access control
- token transfers
- coupon calculations
- bond maturity
- events for transparency

The contract stores essential bond data in a `BondDetails` struct and manages permissioned investor access through mappings.

### 2. Backend API Layer
Location: `scripts/server.py`

This Python Flask application is the bridge between the frontend and blockchain.

Responsibilities include:

- connecting to an Ethereum-compatible node (Anvil/local RPC)
- compiling and loading contract artifacts
- deploying bond contracts
- reading contract state
- sending transactions with signed wallet keys
- serving API endpoints for UI interactions
- maintaining a local registry file for known bond deployments

This API is designed to work with a local blockchain node and a funded wallet account.

### 3. Frontend UI Layer
Location: `frontend/index.html`

The front-end is a single-page dashboard with three main sections:

- Issuer portal: create a new bond
- Investor dashboard: view balances, pending coupons, and transfer assets
- Admin/KYC portal: whitelist investors, distribute tokens, manage coupons, and mature bonds

It uses Tailwind CSS for styling and fetches data from the Flask backend.

## Repository Structure

```text
.
├── BondSecurityToken.sol          # Main Solidity bond token contract
├── .env.template                  # Sample environment configuration
├── .env                          # Local environment values (not usually committed)
├── requirements.txt               # Python dependency list
├── setup.sh                       # Environment setup script
├── run.sh                        # Runs the app and validates blockchain connectivity
├── debug.sh                      # Debug helper script
├── build/                        # Generated ABI and bytecode artifacts
├── data/                         # Local registry storage for deployed bonds
├── frontend/
│   └── index.html                # Browser UI for the platform
├── scripts/
│   ├── compile.py                 # Compiles the Solidity contract
│   └── server.py                  # Flask backend that interacts with blockchain
└── README.md                     # Project documentation
```

## Smart Contract Design

The main contract, `BondSecurityToken`, includes these core components:

### State Variables
- `name`, `symbol`, `decimals`, `totalSupply`
- investor balances and allowance mappings
- allowlist and blacklist mappings
- bond metadata structure
- owner, custodian, issuer addresses
- coupon tracking variables

### Bond Metadata
The `BondDetails` struct stores:

- ISIN
- face value
- coupon rate
- issue date
- maturity date
- coupon frequency
- active/inactive status

### Access Control
The contract uses modifiers such as:

- `onlyOwner`
- `onlyCustodian`
- `onlyAllowlisted(address account)`
- `bondActive`

These enforce permission rules across issuance, transfers, coupon operations, and maturity.

### Events
The contract emits events such as:

- `Transfer`
- `Approval`
- `InvestorWhitelisted`
- `InvestorBlacklisted`
- `CouponDistributed`
- `CouponClaimed`
- `BondMatured`
- `TransferBlocked`

These are useful for monitoring transaction flow and debugging the bond lifecycle.

## Workflow

A typical flow in this project is:

1. Start a local blockchain node such as Anvil.
2. Configure the environment variables in `.env`.
3. Compile the contract with `scripts/compile.py`.
4. Launch the Flask backend.
5. Open the frontend dashboard.
6. Create a bond from the Issuer Portal.
7. Whitelist KYC-approved investors.
8. Distribute tokens to investor wallets.
9. Check balances and pending coupons.
10. Trigger coupon distribution for the bond.
11. Allow investors to claim coupons.
12. Mature the bond when the term ends.

## Environment Requirements

The project depends on:

- Python 3
- Node/Anvil-compatible Ethereum local environment
- An installed wallet private key for the deployer account
- RPC access to a blockchain node

## Required Python Dependencies

See `requirements.txt`:

- Flask
- Flask-CORS
- web3
- eth-account
- py-solc-x
- python-dotenv

## Setup Instructions

### 1. Clone the repository

```bash
git clone https://github.com/sanjayofficialworks-ai/tokenisation.git
cd tokenisation
```

### 2. Create a virtual environment and install dependencies

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 3. Configure environment variables

```bash
cp .env.template .env
```

Then fill in values like:

```env
RPC_URL=http://127.0.0.1:8545
CHAIN_ID=31337
PORT=5000
PRIVATE_KEY=your_anvil_account_0_private_key_here
```

### 4. Start a local blockchain node

```bash
anvil
```

### 5. Compile the contract

```bash
python3 scripts/compile.py
```

### 6. Run the platform

```bash
./run.sh
```

or manually:

```bash
source .venv/bin/activate
python3 scripts/server.py
```

Then open:

```text
http://localhost:5000
```

## API Overview

The backend exposes several endpoints for the bond management process.

### Health check
- `GET /api/health`

### Bond registry
- `GET /api/bonds`
- `POST /api/bonds`

### Bond information
- `GET /api/bonds/<address>/details`
- `GET /api/bonds/<address>/balance/<holder>`

### Investor actions
- `POST /api/bonds/<address>/whitelist`
- `POST /api/bonds/<address>/transfer`
- `POST /api/bonds/<address>/coupon/distribute`
- `POST /api/bonds/<address>/coupon/claim`
- `GET /api/bonds/<address>/coupon/pending/<holder>`
- `POST /api/bonds/<address>/mature`

These endpoints are designed to be consumed by the frontend dashboard and can also be used for direct testing.

## Security and Production Readiness Notes

This project is a learning and demonstration prototype. It is not intended as a production-ready financial system.

Important considerations for a real deployment include:

- formal security audits of the Solidity code
- secure custody and key management
- robust KYC and AML compliance processes
- legal/regulatory review for financial instruments
- stablecoin or fiat settlement rails
- multi-signature governance for protocol administration
- proper monitoring and alerting infrastructure
- production-grade RPC, database, and deployment architecture

## Limitations in the Current Implementation

Some business logic is simplified for demo purposes, including:

- the coupon claim mechanism is recorded on-chain rather than fully integrated with real payment settlement
- the bond lifecycle is not tied to an external real-world bond registry
- investor onboarding is modeled as a simple allowlist workflow
- there is no mature identity, compliance, or audit backend

## Use Cases

This project is useful for:

- blockchain education
- smart-contract demos
- digital securities prototyping
- bond tokenization workshops
- financial product concept validation

## Summary

This repository demonstrates a simplified digital bond platform where corporate debt is represented as a blockchain token with ownership, coupon logic, compliance checks, and lifecycle controls. It combines Solidity, Python, and a lightweight front-end dashboard to model the full workflow of issuance and servicing in an accessible, demo-friendly format.

## License

No explicit license file is currently present in the repository, so license terms should be confirmed before reuse or distribution.

---

If you want, I can also add:

- a more polished project logo section
- screenshots or architecture diagram text
- a section for contributors and roadmap
- a version tailored for GitHub presentation with badges and quick-start commands
