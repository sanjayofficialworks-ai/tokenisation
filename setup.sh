#!/bin/bash

# Dynamic Bond Tokenization Platform Setup Script
echo "🚀 Setting up Dynamic Bond Tokenization Platform..."

# Create project structure
echo "📁 Creating project structure..."
mkdir -p build
mkdir -p data
mkdir -p scripts
mkdir -p static

# Create virtual environment
echo "🐍 Creating virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install dependencies
echo "📦 Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Make scripts executable
chmod +x scripts/compile.py
chmod +x scripts/server.py

# Create .env template
echo "⚙️ Creating environment template..."
cat > .env.template << 'EOF'
# Blockchain Configuration
RPC_URL=http://127.0.0.1:8545
CHAIN_ID=31337

# Server Configuration  
PORT=5000

# Account Configuration (Get from Anvil output)
PRIVATE_KEY=your_anvil_account_0_private_key_here
EOF

echo "✅ Setup complete!"
echo ""
echo "🔧 Next steps:"
echo "1. Start Anvil in a new terminal:"
echo "   anvil"
echo ""
echo "2. Copy the private key of account (0) from Anvil output"
echo ""
echo "3. Set environment variables:"
echo "   export RPC_URL=http://127.0.0.1:8545"
echo "   export PRIVATE_KEY=<anvil-account-0-private-key>"
echo "   export CHAIN_ID=31337"
echo ""
echo "4. Compile the contract:"
echo "   source venv/bin/activate"
echo "   python3 scripts/compile.py"
echo ""
echo "5. Start the server:"
echo "   python3 scripts/server.py"
echo ""
echo "6. Open http://localhost:5000 in your browser"
echo ""
echo "📋 Demo Script:"
echo "   - Issuer creates bond via UI form"
echo "   - Admin whitelists 2 investor addresses" 
echo "   - Admin distributes tokens to investors"
echo "   - Investors check balances"
echo "   - Admin triggers coupon distribution"
echo "   - Investors claim coupons"
echo "   - Admin matures bond (optional)"
echo ""
echo "🎯 All set! The platform is ready for dynamic bond tokenization."