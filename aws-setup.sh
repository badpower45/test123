#!/bin/bash
# AWS EC2 Setup Script for Oldies Workers Server
# Run this on your EC2 instance: ubuntu@16.171.208.249

set -e

echo "🚀 Installing Node.js 20.x LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

echo "📦 Verifying installation..."
node --version
npm --version

echo "🔧 Installing PM2 globally..."
sudo npm install -g pm2

echo "📁 Creating project directory..."
mkdir -p ~/oldies-server
cd ~/oldies-server

echo "✅ Setup complete!"
echo "Next steps:"
echo "1. Upload your code to ~/oldies-server"
echo "2. Create .env file with DATABASE_URL"
echo "3. Run: npm install"
echo "4. Run: npm run build"
echo "5. Run: pm2 start ecosystem.config.js"
