#!/bin/bash

echo "🔍 Debugging Bond Platform Connection Issues"
echo "============================================="

BASE_URL="http://localhost:5000/api"

echo "📊 Step 1: Health Check"
echo "-----------------------"
HEALTH=$(curl -s $BASE_URL/health)
echo $HEALTH | jq '.'

if echo $HEALTH | jq -e '.status == "ok"' > /dev/null; then
    echo "✅ Server is healthy"
else
    echo "❌ Server health check failed"
    echo "Make sure:"
    echo "  1. Flask server is running (python backend/app.py)"
    echo "  2. Anvil is running (anvil)"
    echo "  3. Environment variables are set"
    exit 1
fi

echo ""
echo "📜 Step 2: List All Bonds"
echo "-------------------------"
BONDS=$(curl -s $BASE_URL/bonds)
echo $BONDS | jq '.'

BOND_COUNT=$(echo $BONDS | jq '.bonds | length')
echo "Bond Count: $BOND_COUNT"

if [ "$BOND_COUNT" -gt 0 ]; then
    echo "✅ Found $BOND_COUNT bond(s)"
    
    # Get the first bond address
    FIRST_BOND=$(echo $BONDS | jq -r '.bonds[0].address // empty')
    if [ -n "$FIRST_BOND" ] && [ "$FIRST_BOND" != "null" ]; then
        echo "🎯 Testing with bond: $FIRST_BOND"
        
        echo ""
        echo "📋 Step 3: Test Bond Details"
        echo "----------------------------"
        curl -s $BASE_URL/bonds/$FIRST_BOND/details | jq '.'
        
        echo ""
        echo "💰 Step 4: Test Balance Check (Deployer)"
        echo "----------------------------------------"
        curl -s $BASE_URL/bonds/$FIRST_BOND/balance/0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 | jq '.'
        
    else
        echo "❌ No valid bond address found"
    fi
else
    echo "❌ No bonds found. You need to create a bond first."
    echo ""
    echo "🛠️  Create a bond using this command:"
    echo "curl -X POST $BASE_URL/bonds \\"
    echo "  -H \"Content-Type: application/json\" \\"
    echo "  -d '{"
    echo "    \"name\": \"Test Bond\","
    echo "    \"symbol\": \"TEST\","
    echo "    \"total_supply\": 1000,"
    echo "    \"custodian\": \"0x70997970C51812dc3A010C7d01b50e0d17dc79C8\","
    echo "    \"issuer\": \"0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC\","
    echo "    \"isin\": \"TEST123456\","
    echo "    \"face_value\": 1000,"
    echo "    \"coupon_rate\": 500,"
    echo "    \"maturity_years\": 5,"
    echo "    \"coupon_frequency\": 2"
    echo "  }'"
fi

echo ""
echo "🔧 Environment Check"
echo "--------------------"
echo "PRIVATE_KEY: ${PRIVATE_KEY:0:10}... (${#PRIVATE_KEY} chars)"
echo "RPC_URL: $RPC_URL"
echo "CHAIN_ID: $CHAIN_ID"

echo ""
echo "💡 Troubleshooting Tips:"
echo "1. If health check fails: restart Flask server"
echo "2. If no bonds found: create a new bond via frontend"
echo "3. If Anvil restarted: all old contract addresses are invalid"
echo "4. Check Flask server logs for detailed error messages"