#!/usr/bin/env python3
import json, os
from pathlib import Path
from solcx import compile_source, install_solc, set_solc_version, get_installed_solc_versions

SOLC_VER = "0.8.19"

def ensure_solc(ver: str = SOLC_VER):
    # install if missing, then activate
    if ver not in {str(v) for v in get_installed_solc_versions()}:
        print(f"Installing solc {ver} ...")
        install_solc(ver)
    set_solc_version(ver)
    print(f"Using solc {ver}")

def compile_contract():
    ensure_solc(SOLC_VER)

    # Determine contract path (env override or project root)
    env_contract = os.getenv("CONTRACT_PATH")
    if env_contract and Path(env_contract).exists():
        contract_path = Path(env_contract)
    else:
        contract_path = Path(__file__).parent.parent / "BondSecurityToken.sol"

    if not contract_path.exists():
        raise FileNotFoundError(f"Contract file not found at: {contract_path}")

    print("Compiling BondSecurityToken.sol...")
    source = contract_path.read_text()

    compiled = compile_source(
        source,
        output_values=["abi", "bin"]
    )

    _, artifact = compiled.popitem()

    build_dir = Path(__file__).parent.parent / "build"
    build_dir.mkdir(exist_ok=True)

    abi_path = build_dir / "BondSecurityToken.abi.json"
    bin_path = build_dir / "BondSecurityToken.bin"

    abi_path.write_text(json.dumps(artifact["abi"], indent=2))
    bin_path.write_text(artifact["bin"])

    print(f"Contract compiled successfully!")
    print(f"ABI  -> {abi_path}")
    print(f"BIN  -> {bin_path}")

if __name__ == "__main__":
    compile_contract()
