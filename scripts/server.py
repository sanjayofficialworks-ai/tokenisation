#!/usr/bin/env python3
import json
import os
from pathlib import Path
from datetime import datetime
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from web3 import Web3
from eth_account import Account
import traceback

# ──────────────────────────────────────────────────────────────────────────────
# App / Config
# ──────────────────────────────────────────────────────────────────────────────
app = Flask(__name__, static_folder='../frontend')  # serve SPA
CORS(app)

RPC_URL   = os.getenv('RPC_URL', 'http://127.0.0.1:8545')
PRIVATE_KEY = os.getenv('PRIVATE_KEY')
CHAIN_ID  = int(os.getenv('CHAIN_ID', '31337'))
PORT      = int(os.getenv('PORT', '5000'))

if not PRIVATE_KEY:
    raise ValueError("PRIVATE_KEY environment variable is required")

# ──────────────────────────────────────────────────────────────────────────────
# Web3 setup
# ──────────────────────────────────────────────────────────────────────────────
w3 = Web3(Web3.HTTPProvider(RPC_URL))
account = Account.from_key(PRIVATE_KEY)

print(f"[server] RPC: {RPC_URL}")
print(f"[server] Chain ID: {CHAIN_ID}")
print(f"[server] Deployer: {account.address}")
try:
    bal = w3.eth.get_balance(account.address)
    print(f"[server] Balance: {w3.from_wei(bal, 'ether')} ETH")
except Exception as e:
    print(f"[server] Warning: could not read balance: {e}")

# ──────────────────────────────────────────────────────────────────────────────
# Artifacts
# ──────────────────────────────────────────────────────────────────────────────
def load_contract_artifacts():
    base_dir = Path(__file__).parent.parent
    abi_path = base_dir / 'build' / 'BondSecurityToken.abi.json'
    bin_path = base_dir / 'build' / 'BondSecurityToken.bin'
    if not abi_path.exists() or not bin_path.exists():
        raise FileNotFoundError("Contract artifacts not found. Run scripts/compile.py first.")
    with open(abi_path, 'r') as f:
        abi = json.load(f)
    with open(bin_path, 'r') as f:
        bytecode = f.read().strip()
    return abi, bytecode

CONTRACT_ABI, CONTRACT_BYTECODE = load_contract_artifacts()

# ──────────────────────────────────────────────────────────────────────────────
# Registry (simple JSON file)
# ──────────────────────────────────────────────────────────────────────────────
REGISTRY_FILE = Path(__file__).parent.parent / 'data' / 'registry.json'
REGISTRY_FILE.parent.mkdir(exist_ok=True)

def load_registry():
    if REGISTRY_FILE.exists():
        with open(REGISTRY_FILE, 'r') as f:
            try:
                data = json.load(f)
                # keep only valid rows
                return [
                    r for r in data
                    if isinstance(r, dict)
                    and isinstance(r.get("address"), str)
                    and r["address"].startswith("0x")
                    and len(r["address"]) == 42
                ]
            except Exception:
                return []
    return []

def save_registry(bonds):
    with open(REGISTRY_FILE, 'w') as f:
        json.dump(bonds, f, indent=2)

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────
def _txhash_hex(receipt):
    """Extract transaction hash as hex string from receipt"""
    if hasattr(receipt, 'transactionHash'):
        tx_hash = receipt.transactionHash
    elif isinstance(receipt, dict) and 'transactionHash' in receipt:
        tx_hash = receipt['transactionHash']
    else:
        return None
    
    # Convert to hex if it's bytes
    if isinstance(tx_hash, bytes):
        return tx_hash.hex()
    elif isinstance(tx_hash, str):
        return tx_hash
    else:
        return str(tx_hash)

def _get_contract_address(receipt):
    """Extract contract address from deployment receipt"""
    if hasattr(receipt, 'contractAddress'):
        addr = receipt.contractAddress
    elif isinstance(receipt, dict) and 'contractAddress' in receipt:
        addr = receipt['contractAddress']
    else:
        return None
    
    if addr is None:
        return None
    
    # Ensure it's a string and properly formatted
    addr_str = str(addr) if not isinstance(addr, str) else addr
    if addr_str.startswith('0x') and len(addr_str) == 42:
        return Web3.to_checksum_address(addr_str)
    return None

def _checksum(addr: str) -> str:
    """Convert address to checksum format with proper validation"""
    if not isinstance(addr, str):
        raise ValueError(f"Address must be string, got: {type(addr)}")
    
    addr = addr.strip()
    if not addr.startswith("0x"):
        raise ValueError(f"Address must start with 0x: {addr}")
    
    if len(addr) != 42:
        raise ValueError(f"Address must be 42 characters: {addr}")
    
    try:
        return Web3.to_checksum_address(addr)
    except ValueError as e:
        raise ValueError(f"Invalid address format: {addr} - {e}")

def _bad_request(msg, code=400):
    print(f"[server] Bad request: {msg}")
    return jsonify({"error": msg}), code

def _check_contract_exists(address):
    """Check if contract exists at given address"""
    try:
        code = w3.eth.get_code(address)
        return code != b''
    except Exception:
        return False

def send_transaction(tx: dict):
    """
    Sign & send any tx (constructor or method) with proper error handling
    """
    try:
        # Clean the transaction dict - remove any None values
        clean_tx = {k: v for k, v in tx.items() if v is not None}
        
        # Ensure from address is set
        clean_tx["from"] = account.address

        print(f"[server] Preparing transaction: {clean_tx}")

        # Estimate gas with better error handling
        try:
            est = w3.eth.estimate_gas(clean_tx)
            clean_tx["gas"] = max(int(est * 1.25), est + 50000)  # Add buffer
            print(f"[server] Gas estimated: {est}, using: {clean_tx['gas']}")
        except Exception as e:
            print(f"[server] Gas estimation failed: {e}, using default")
            clean_tx["gas"] = 5_000_000

        # Handle fee structure based on EIP-1559 support
        try:
            latest_block = w3.eth.get_block("latest")
            if "baseFeePerGas" in latest_block:
                # EIP-1559 transaction
                base_fee = latest_block["baseFeePerGas"]
                tip = w3.to_wei("2", "gwei")
                clean_tx["maxPriorityFeePerGas"] = tip
                clean_tx["maxFeePerGas"] = base_fee + tip
                print(f"[server] Using EIP-1559 fees: base={base_fee}, tip={tip}")
            else:
                # Legacy transaction
                clean_tx["gasPrice"] = w3.to_wei("20", "gwei")
                print(f"[server] Using legacy gas price: {clean_tx['gasPrice']}")
        except Exception as e:
            print(f"[server] Fee estimation failed: {e}, using legacy pricing")
            clean_tx["gasPrice"] = w3.to_wei("20", "gwei")

        # Set nonce and chain ID
        clean_tx["nonce"] = w3.eth.get_transaction_count(account.address)
        clean_tx["chainId"] = CHAIN_ID
        
        print(f"[server] Final transaction: {clean_tx}")

        # Sign and send
        signed = w3.eth.account.sign_transaction(clean_tx, PRIVATE_KEY)
        print(f"[server] Transaction signed, sending...")
        
        tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
        print(f"[server] Transaction sent: {tx_hash.hex()}")
        
        receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
        print(f"[server] Transaction receipt: {receipt}")

        # Check transaction status
        status = receipt.get("status", 1) if isinstance(receipt, dict) else getattr(receipt, "status", 1)
        if status != 1:
            raise RuntimeError(f"Transaction reverted: {receipt}")
            
        return receipt

    except Exception as e:
        print(f"[server] Transaction failed: {e}")
        print(traceback.format_exc())
        raise

# ──────────────────────────────────────────────────────────────────────────────
# Routes
# ──────────────────────────────────────────────────────────────────────────────
@app.route('/')
def serve_frontend():
    return send_from_directory(app.static_folder, 'index.html')

@app.route('/api/health')
def health():
    try:
        return jsonify({
            "status": "ok",
            "rpc": RPC_URL,
            "latest_block": w3.eth.block_number,
            "account": account.address,
            "chain_id": CHAIN_ID,
            "timestamp": datetime.now().isoformat()
        })
    except Exception as e:
        print(f"[server] Health check failed: {e}")
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/api/bonds', methods=['GET'])
def get_bonds():
    try:
        bonds = load_registry()
        # Add contract existence check
        for bond in bonds:
            bond["exists"] = _check_contract_exists(bond["address"])
        return jsonify({"bonds": bonds})
    except Exception as e:
        print(f"[server] Error loading bonds: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds', methods=['POST'])
def create_bond():
    try:
        print("[server] Creating new bond...")
        data = request.get_json(force=True, silent=False)
        print(f"[server] Received data: {data}")
        
        required = ['name','symbol','total_supply','custodian','issuer','isin','face_value','coupon_rate','maturity_years','coupon_frequency']
        for f in required:
            if f not in data:
                return _bad_request(f"Missing field: {f}")

        # Validate and convert addresses
        try:
            custodian_addr = _checksum(str(data['custodian']))
            issuer_addr = _checksum(str(data['issuer']))
        except ValueError as e:
            return _bad_request(f"Invalid address: {e}")

        # Validate numeric fields
        try:
            total_supply = int(data['total_supply'])
            face_value = int(data['face_value'])
            coupon_rate = int(data['coupon_rate'])
            maturity_years = int(data['maturity_years'])
            coupon_frequency = int(data['coupon_frequency'])
            
            if total_supply <= 0 or face_value <= 0 or maturity_years <= 0 or coupon_frequency <= 0:
                return _bad_request("Numeric fields must be positive")
            if coupon_rate < 0:
                return _bad_request("Coupon rate cannot be negative")
                
        except (ValueError, TypeError) as e:
            return _bad_request(f"Invalid numeric field: {e}")

        # Build constructor arguments - FIX: multiply total_supply by 10^18
        constructor_args = [
            str(data['name']),
            str(data['symbol']),
            total_supply * (10**18),  # FIX: Convert to proper token amount with 18 decimals
            custodian_addr,
            issuer_addr,
            str(data['isin']),
            face_value,
            coupon_rate,
            maturity_years,
            coupon_frequency,
        ]
        
        print(f"[server] Constructor args: {constructor_args}")

        # Create contract instance and build transaction
        contract = w3.eth.contract(abi=CONTRACT_ABI, bytecode=CONTRACT_BYTECODE)
        
        # Build the deployment transaction
        constructor_txn = contract.constructor(*constructor_args).build_transaction({
            "from": account.address
        })
        
        print(f"[server] Built constructor transaction")
        
        # Send the transaction
        receipt = send_transaction(constructor_txn)
        
        # Get contract address and transaction hash
        contract_address = _get_contract_address(receipt)
        tx_hex = _txhash_hex(receipt)

        if not contract_address:
            raise RuntimeError("Failed to get contract address from receipt")

        print(f"[server] Bond deployed at: {contract_address}")

        # Update registry
        bonds = load_registry()
        bond_record = {
            "address": contract_address,
            "name": data["name"],
            "symbol": data["symbol"],
            "tx": tx_hex,
            "isin": data["isin"],
            "total_supply": total_supply,
            "face_value": face_value,
            "coupon_rate": coupon_rate,
            "maturity_years": maturity_years,
            "coupon_frequency": coupon_frequency,
            "custodian": custodian_addr,
            "issuer": issuer_addr,
            "created_at": datetime.now().isoformat(),
            "deployer": account.address,
            "exists": True
        }
        bonds.append(bond_record)
        save_registry(bonds)

        print(f"[server] Bond created successfully: {contract_address}")
        return jsonify({
            "status": "created", 
            "address": contract_address, 
            "tx": tx_hex,
            "bond": bond_record
        })

    except ValueError as ve:
        print(f"[server] Validation error: {ve}")
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Unexpected error creating bond: {e}")
        print(traceback.format_exc())
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/details')
def bond_details(address):
    try:
        print(f"[server] Getting details for bond: {address}")
        contract_addr = _checksum(address)
        
        # Check if contract exists
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        try:
            name = c.functions.name().call()
            symbol = c.functions.symbol().call()
            total_supply = c.functions.totalSupply().call()
            
            # Get bond details with error handling
            details = c.functions.getBondDetails().call()
            print(f"[server] Bond details raw: {details}")
            print(f"[server] Bond details length: {len(details)}")
            
            # Handle different return formats
            if len(details) >= 8:
                bond_details = {
                    "isin": details[0],
                    "face_value": details[1],
                    "coupon_bps": details[2],
                    "issueDate": details[3],
                    "maturityDate": details[4],
                    "coupon_per_year": details[5],
                    "isActive": details[6],
                    "currentPeriod": details[7],
                }
            elif len(details) >= 7:
                bond_details = {
                    "isin": details[0],
                    "face_value": details[1],
                    "coupon_bps": details[2],
                    "issueDate": details[3],
                    "maturityDate": details[4],
                    "coupon_per_year": details[5],
                    "isActive": details[6],
                    "currentPeriod": 0,
                }
            elif len(details) >= 6:
                bond_details = {
                    "isin": details[0],
                    "face_value": details[1],
                    "coupon_bps": details[2],
                    "issueDate": details[3],
                    "maturityDate": details[4],
                    "coupon_per_year": details[5],
                    "isActive": True,
                    "currentPeriod": 0,
                }
            elif len(details) >= 5:
                bond_details = {
                    "isin": details[0],
                    "face_value": details[1],
                    "coupon_bps": details[2],
                    "issueDate": details[3],
                    "maturityDate": details[4],
                    "coupon_per_year": 4,
                    "isActive": True,
                    "currentPeriod": 0,
                }
            else:
                return _bad_request(f"Unexpected bond details format: {details}")
            
            return jsonify({
                "name": name,
                "symbol": symbol,
                "totalSupply": total_supply // (10**18),
                "details": bond_details
            })
        except Exception as call_error:
            print(f"[server] Contract call error: {call_error}")
            return _bad_request(f"Contract call failed: {str(call_error)}")
            
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Error getting bond details: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/balance/<holder>')
def get_balance(address, holder):
    try:
        contract_addr = _checksum(address)
        holder_addr = _checksum(holder)
        
        # Check if contract exists
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        try:
            bal = c.functions.balanceOf(holder_addr).call()
            return jsonify({"address": holder_addr, "balance": bal // (10**18)})
        except Exception as call_error:
            return _bad_request(f"Contract call failed: {str(call_error)}")
            
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Error getting balance: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/debug')
def debug_bond(address):
    try:
        contract_addr = _checksum(address)
        
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        debug_info = {
            "contract_address": contract_addr,
            "exists": True
        }
        
        try:
            debug_info["name"] = c.functions.name().call()
            debug_info["symbol"] = c.functions.symbol().call()
            debug_info["totalSupply"] = c.functions.totalSupply().call()
            debug_info["totalSupply_tokens"] = debug_info["totalSupply"] // (10**18)
            debug_info["decimals"] = c.functions.decimals().call()
            
            # Check deployer balance
            deployer_balance = c.functions.balanceOf(account.address).call()
            debug_info["deployer_balance"] = deployer_balance
            debug_info["deployer_balance_tokens"] = deployer_balance // (10**18)
            
            # Try to get bond details
            try:
                details = c.functions.getBondDetails().call()
                debug_info["bond_details"] = details
                debug_info["bond_details_length"] = len(details)
                debug_info["bond_details_types"] = [type(d).__name__ for d in details]
            except Exception as e:
                debug_info["bond_details_error"] = str(e)
            
            # Check if contract has common functions
            try:
                debug_info["owner"] = c.functions.owner().call()
            except:
                debug_info["owner"] = "function not found"
                
            try:
                debug_info["custodian"] = c.functions.custodian().call()
            except:
                debug_info["custodian"] = "function not found"
                
            try:
                debug_info["issuer"] = c.functions.issuer().call()
            except:
                debug_info["issuer"] = "function not found"
                
        except Exception as e:
            debug_info["contract_error"] = str(e)
        
        return jsonify(debug_info)
        
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/whitelist', methods=['POST'])
def whitelist(address):
    try:
        print(f"[server] Whitelisting investor for bond: {address}")
        data = request.get_json(force=True, silent=False)
        
        if "investor" not in data or "kycId" not in data:
            return _bad_request("Missing investor or kycId")
        
        investor_addr = _checksum(str(data["investor"]))
        kyc_id = str(data["kycId"])
        
        contract_addr = _checksum(address)
        
        # Check if contract exists
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        build = c.functions.addToWhitelist(investor_addr, kyc_id).build_transaction({
            "from": account.address
        })
        
        receipt = send_transaction(build)
        return jsonify({"status": "ok", "tx": _txhash_hex(receipt)})
        
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Error whitelisting: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/transfer', methods=['POST'])
def transfer(address):
    try:
        print(f"[server] Transferring tokens for bond: {address}")
        data = request.get_json(force=True, silent=False)
        
        if "to" not in data or "amount" not in data:
            return _bad_request("Missing to or amount")
        
        to_addr = _checksum(str(data["to"]))
        try:
            amount_whole = int(data["amount"])
        except (ValueError, TypeError):
            return _bad_request("Amount must be a valid integer")
            
        if amount_whole <= 0:
            return _bad_request("Amount must be positive")
        
        amt = amount_whole * (10**18)
        
        contract_addr = _checksum(address)
        
        # Check if contract exists
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        build = c.functions.transfer(to_addr, amt).build_transaction({
            "from": account.address
        })
        
        receipt = send_transaction(build)
        return jsonify({"status": "ok", "tx": _txhash_hex(receipt)})
        
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Error transferring: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/coupon/distribute', methods=['POST'])
def coupon_distribute(address):
    try:
        print(f"[server] Distributing coupons for bond: {address}")
        contract_addr = _checksum(address)
        
        # Check if contract exists
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        build = c.functions.distributeCoupons().build_transaction({
            "from": account.address
        })
        
        receipt = send_transaction(build)
        return jsonify({"status": "ok", "tx": _txhash_hex(receipt)})
        
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Error distributing coupons: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/coupon/claim', methods=['POST'])
def coupon_claim(address):
    try:
        print(f"[server] Claiming coupons for bond: {address}")
        contract_addr = _checksum(address)
        
        # Check if contract exists
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        build = c.functions.claimCoupons().build_transaction({
            "from": account.address
        })
        
        receipt = send_transaction(build)
        return jsonify({"status": "ok", "tx": _txhash_hex(receipt)})
        
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Error claiming coupons: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/coupon/pending/<holder>')
def coupon_pending(address, holder):
    try:
        contract_addr = _checksum(address)
        holder_addr = _checksum(holder)
        
        # Check if contract exists
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        try:
            pending = c.functions.pendingCoupons(holder_addr).call()
            return jsonify({"address": holder_addr, "pendingCoupons": pending})
        except Exception as call_error:
            return _bad_request(f"Contract call failed: {str(call_error)}")
            
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Error getting pending coupons: {e}")
        return jsonify({"error": str(e)}), 500

@app.route('/api/bonds/<address>/mature', methods=['POST'])
def mature(address):
    try:
        print(f"[server] Maturing bond: {address}")
        contract_addr = _checksum(address)
        
        # Check if contract exists
        if not _check_contract_exists(contract_addr):
            return _bad_request(f"No contract deployed at address: {contract_addr}")
        
        c = w3.eth.contract(address=contract_addr, abi=CONTRACT_ABI)
        
        build = c.functions.matureBond().build_transaction({
            "from": account.address
        })
        
        receipt = send_transaction(build)
        return jsonify({"status": "ok", "tx": _txhash_hex(receipt)})
        
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        print(f"[server] Error maturing bond: {e}")
        return jsonify({"error": str(e)}), 500

# Debug route to check contract status
@app.route('/api/debug/contract/<address>')
def debug_contract(address):
    try:
        contract_addr = _checksum(address)
        exists = _check_contract_exists(contract_addr)
        
        result = {
            "address": contract_addr,
            "exists": exists,
        }
        
        if exists:
            try:
                code = w3.eth.get_code(contract_addr)
                result["code_length"] = len(code)
                result["has_code"] = len(code) > 0
            except Exception as e:
                result["code_error"] = str(e)
        
        return jsonify(result)
        
    except ValueError as ve:
        return _bad_request(str(ve))
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# Error handlers
@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Not found"}), 404

@app.errorhandler(500)
def server_error(e):
    print(f"[server] Internal server error: {e}")
    return jsonify({"error": "Internal server error"}), 500

# ──────────────────────────────────────────────────────────────────────────────
if __name__ == '__main__':
    print(f"[server] Starting on :{PORT}")
    print(f"[server] Connected to chain ID: {CHAIN_ID}")
    print(f"[server] Account: {account.address}")
    
    try:
        # Test connection
        latest_block = w3.eth.block_number
        print(f"[server] Latest block: {latest_block}")
        print(f"[server] Server ready!")
    except Exception as e:
        print(f"[server] Warning: Could not connect to blockchain: {e}")
    
    app.run(host='0.0.0.0', port=PORT, debug=True)
