# Dynamic Bond Tokenization Platform

> **A prototype for exploring permissioned corporate-bond tokens on an Ethereum-compatible blockchain.**
>
> Solidity contract · Python/Flask API · Browser dashboard

This repository demonstrates a simplified bond lifecycle: deploy a bond token, allowlist investors, transfer tokens, record coupon claims, and mark the bond as matured. It is intended for learning and local development—not for issuing, selling, or servicing real financial securities.

## At a glance

- **Smart contract:** Solidity `BondSecurityToken` with bond metadata, token balances, allowlisting, transfers, coupon bookkeeping, and maturity state.
- **Backend:** Flask API using Web3.py to read from and submit transactions to an Ethereum-compatible JSON-RPC node.
- **Frontend:** Single-page HTML/JavaScript dashboard for issuer, investor, and admin demo flows.
- **Local development:** Designed to be exercised with a local node such as Anvil.

## What the demo shows

1. Create a bond contract with an ISIN, face value, coupon rate, maturity, and coupon frequency.
2. Add investor wallet addresses to the contract allowlist.
3. Transfer tokens to eligible wallets and inspect balances.
4. Trigger coupon bookkeeping and view or claim the recorded amount.
5. Mark the bond as matured once its maturity date has passed.

The contract initially allocates the full token supply to the custodian. The server signs transactions with the configured `PRIVATE_KEY`; for the demo, that account must have the appropriate contract role for the action being performed.

## Why Solidity?

Solidity is used because the bond's core rules and state need to execute on an Ethereum-compatible blockchain rather than only inside the web server. A smart contract provides a shared, transaction-based record of token balances and bond lifecycle actions, and can enforce permission checks consistently when transactions are submitted.

For this prototype, Solidity makes it possible to demonstrate:

- **On-chain state:** bond metadata, balances, allowlist status, coupon bookkeeping, and maturity status are stored in the contract.
- **Enforced rules:** contract functions check the caller's role, investor eligibility, available balance, and bond state before changing state.
- **Transparent activity:** events such as transfers, allowlisting, coupon distribution, claims, and maturity can be inspected from transaction logs.
- **EVM compatibility:** the contract can be compiled with Solidity 0.8.19 and deployed to Anvil or other compatible networks.

Solidity does not itself verify a person's identity or settle a real-world bond. In this application, KYC is represented by an administrator-managed allowlist, and coupon claims are bookkeeping only. See [Important prototype limitations](#important-prototype-limitations).

## Architecture

```text
┌──────────────────────────────┐
│ Browser dashboard            │
│ frontend/index.html          │
└──────────────┬───────────────┘
               │ HTTP / JSON
               ▼
┌──────────────────────────────┐
│ Flask API                    │
│ scripts/server.py            │
│ - serves the dashboard       │
│ - validates inputs           │
│ - reads/signs chain calls    │
│ - stores local bond registry │
└──────────────┬───────────────┘
               │ JSON-RPC (Web3.py)
               ▼
┌──────────────────────────────┐
│ Ethereum-compatible node     │
│ e.g. local Anvil             │
└──────────────┬───────────────┘
               │
               ▼
┌──────────────────────────────┐
│ BondSecurityToken.sol        │
│ deployed bond token contract │
└──────────────────────────────┘
```

### Main components

| Component | Location | Responsibility |
| --- | --- | --- |
| Bond contract | `BondSecurityToken.sol` | Stores bond and token state; enforces allowlist and role checks; emits lifecycle events. |
| Compiler script | `scripts/compile.py` | Compiles the Solidity source with Solidity 0.8.19 and writes ABI/bytecode to `build/`. |
| API server | `scripts/server.py` | Serves the UI and API, connects to the configured RPC, deploys contracts, and submits signed transactions. |
| Dashboard | `frontend/index.html` | Provides forms and views for bond creation, balances, transfers, allowlisting, coupons, and maturity. |
| Local registry | `data/registry.json` | Stores a local list of bond deployments known to the server. It is not an authoritative on-chain registry. |

## Frontend dashboard

The frontend is a single HTML page at `frontend/index.html`. It calls the Flask API at the same origin and presents the demo workflows in three panels:

- **Issuer Portal:** enter bond name, symbol, ISIN, supply, face value, coupon rate, maturity, coupon frequency, custodian, and issuer; submit the form to deploy a contract.
- **Investor Dashboard:** select a registered bond, inspect bond details, check a wallet's token balance and pending coupon amount, claim coupons, or transfer tokens.
- **Admin/KYC Portal:** allowlist an investor with a KYC ID, distribute tokens, trigger coupon bookkeeping, and request maturity.
- **System Status:** display the bond count, network status, and latest block number. The page refreshes network status periodically.

The dashboard reports success or errors as notifications and displays the newly deployed contract address and transaction hash after bond creation. Its controls are a demo interface; actions still depend on the backend's configured signing account and the access rules in the contract.

## What output to expect

When the application starts successfully, the backend logs its RPC URL, chain ID, signer address, and latest block (when the node is reachable). The browser opens the dashboard at `http://localhost:5000`.

After a successful bond deployment, the UI shows:

- the deployed contract address
- the deployment transaction hash
- the new bond in the bond selector (after the list refreshes)

The API's `GET /api/health` response includes status, RPC URL, latest block, configured account, chain ID, and timestamp. Contract actions return transaction hashes on success. The contract emits events such as `Transfer`, `InvestorWhitelisted`, `CouponDistributed`, `CouponClaimed`, and `BondMatured` for transaction-level inspection.

Compilation generates these local artifacts:

```text
build/BondSecurityToken.abi.json
build/BondSecurityToken.bin
```

The application stores its local bond list in `data/registry.json` when the backend creates deployments.

## Repository layout

```text
.
├── BondSecurityToken.sol       # Solidity contract
├── frontend/
│   └── index.html              # Browser dashboard
├── scripts/
│   ├── compile.py              # Solidity compiler wrapper
│   └── server.py               # Flask API and Web3 integration
├── build/                      # Generated ABI and bytecode
├── data/                       # Local registry data (created at runtime)
├── .env.template               # Environment variable example
├── requirements.txt            # Python dependencies
├── setup.sh                    # Setup helper
├── run.sh                      # Compile and start helper
├── debug.sh                    # Debug helper
└── README.md                   # Project documentation
```

## Quick start (local demo)

### Prerequisites

- Python 3
- [Foundry](https://getfoundry.sh/) installed so you can run Anvil
- A local Anvil account and its private key

> Use only disposable local-development keys. Never use a real wallet key or fund a demo account with valuable assets.

### 1. Clone and install Python dependencies

```bash
git clone https://github.com/sanjayofficialworks-ai/tokenisation.git
cd tokenisation
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### 2. Start Anvil

In a separate terminal:

```bash
anvil
```

Use the RPC URL, chain ID, and a private key printed by Anvil for the local demo.

### 3. Configure the environment

```bash
cp .env.template .env
```

Edit `.env` with the local Anvil account values:

```dotenv
RPC_URL=http://127.0.0.1:8545
CHAIN_ID=31337
PORT=5000
PRIVATE_KEY=<local-anvil-private-key>
```

Keep `.env` and private keys out of version control. The backend uses this private key to sign blockchain transactions.

### 4. Compile and start the application

The compiler installs/uses Solidity 0.8.19 through `py-solc-x` and generates artifacts under `build/`.

```bash
python scripts/compile.py
python scripts/server.py
```

Open <http://localhost:5000> in your browser. The API health check is at <http://localhost:5000/api/health>.

`run.sh` is also available as a convenience runner. It expects a `.venv` virtual environment, a populated `.env`, a reachable RPC node, and the generated build artifacts. The standalone commands above make each step explicit.

## API routes

The UI uses the following Flask API routes:

| Method | Route | Purpose |
| --- | --- | --- |
| `GET` | `/api/health` | Check server/RPC status and report chain information. |
| `GET` | `/api/bonds` | List bond entries in the local registry. |
| `POST` | `/api/bonds` | Deploy a bond contract and add it to the local registry. |
| `GET` | `/api/bonds/<address>/details` | Read token and bond details from a deployed contract. |
| `GET` | `/api/bonds/<address>/balance/<holder>` | Read a holder's token balance. |
| `POST` | `/api/bonds/<address>/whitelist` | Add an investor to the contract allowlist. |
| `POST` | `/api/bonds/<address>/transfer` | Submit a token transfer. |
| `POST` | `/api/bonds/<address>/coupon/distribute` | Trigger coupon accounting on the contract. |
| `POST` | `/api/bonds/<address>/coupon/claim` | Record a coupon claim for the server transaction signer. |
| `GET` | `/api/bonds/<address>/coupon/pending/<holder>` | Read a holder's pending coupon amount. |
| `POST` | `/api/bonds/<address>/mature` | Submit the bond maturity operation. |

## Important prototype limitations

This is a proof-of-concept, not a production financial application. In particular:

- Coupon distribution and claims update contract bookkeeping; **they do not transfer money, stablecoins, or fiat**.
- Maturity changes the contract's active state; **the current contract does not repay principal or burn tokens**.
- KYC is represented by an allowlist and an identifier string. The application does not perform identity verification or provide a compliance service.
- The backend uses one configured private key to sign transactions. It is a trusted demo server, not a user-controlled wallet integration or production custody design.
- The bond registry is a local JSON file and can be lost or changed independently of the blockchain.
- The contract and application have not been presented as audited or legally compliant. Do not use them to issue or trade real securities.

Before any real-world use, the system would need independent smart-contract and application security reviews, appropriate legal/regulatory analysis, secure key custody, real settlement and payment integrations, robust identity/compliance processes, and production-grade infrastructure.

## Technology

- Solidity `^0.8.19`
- Python and Flask
- Web3.py and `eth-account`
- `py-solc-x`
- HTML, JavaScript, and Tailwind CSS
- Anvil for local blockchain development
