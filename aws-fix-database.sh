#!/bin/bash

# 🚀 Quick Fix Script for AWS EC2 Database Connection
# Run this script on your EC2 server after SSH

set -e  # Exit on error

echo "=========================================="
echo "🔧 Oldies Workers - Database Fix Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR=~/oldies-server
DATABASE_URL="postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require"

echo "📁 Project directory: $PROJECT_DIR"
echo ""

# Step 1: Navigate to project directory
echo "Step 1: Navigating to project directory..."
if [ ! -d "$PROJECT_DIR" ]; then
    echo -e "${RED}❌ Directory $PROJECT_DIR does not exist!${NC}"
    echo "Please update PROJECT_DIR variable in this script"
    exit 1
fi
cd "$PROJECT_DIR"
echo -e "${GREEN}✅ In directory: $(pwd)${NC}"
echo ""

# Step 2: Create .env file
echo "Step 2: Creating .env file..."
cat > .env << EOF
# Neon PostgreSQL Database Connection
DATABASE_URL=$DATABASE_URL

# Server Configuration
PORT=5000
NODE_ENV=production
EOF
echo -e "${GREEN}✅ .env file created${NC}"
echo ""

# Step 3: Update ecosystem.config.js
echo "Step 3: Updating ecosystem.config.js..."
cat > ecosystem.config.js << 'EOF'
export default {
  apps: [{
    name: 'oldies-api',
    script: './dist/server/index.js',
    cwd: '/home/ubuntu/oldies-server',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      PORT: 5000,
      DATABASE_URL: 'postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require'
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true
  }]
};
EOF
echo -e "${GREEN}✅ ecosystem.config.js updated${NC}"
echo ""

# Step 4: Install dependencies
echo "Step 4: Installing dependencies..."
npm install
echo -e "${GREEN}✅ Dependencies installed${NC}"
echo ""

# Step 5: Build TypeScript
echo "Step 5: Building TypeScript..."
npm run build
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Build successful${NC}"
else
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi
echo ""

# Step 6: Create logs directory
echo "Step 6: Creating logs directory..."
mkdir -p logs
echo -e "${GREEN}✅ Logs directory ready${NC}"
echo ""

# Step 7: Stop old PM2 instance
echo "Step 7: Stopping old PM2 instance..."
pm2 stop oldies-api 2>/dev/null || echo "No running instance found"
pm2 delete oldies-api 2>/dev/null || echo "No instance to delete"
echo -e "${GREEN}✅ Old instance stopped${NC}"
echo ""

# Step 8: Start fresh PM2 instance
echo "Step 8: Starting new PM2 instance..."
pm2 start ecosystem.config.js
pm2 save
echo -e "${GREEN}✅ PM2 started and saved${NC}"
echo ""

# Step 9: Setup PM2 startup
echo "Step 9: Setting up PM2 startup..."
pm2 startup systemd -u ubuntu --hp /home/ubuntu > /tmp/pm2_startup.sh 2>&1 || true
if [ -f /tmp/pm2_startup.sh ]; then
    cat /tmp/pm2_startup.sh
    echo ""
    echo -e "${YELLOW}⚠️  Please run the command above with sudo if not already done${NC}"
fi
echo ""

# Step 10: Verify everything
echo "=========================================="
echo "✅ Installation Complete!"
echo "=========================================="
echo ""

echo "📊 PM2 Status:"
pm2 status
echo ""

echo "🔍 Testing health endpoint..."
sleep 2
HEALTH_CHECK=$(curl -s http://localhost:5000/health || echo "FAILED")
if [[ $HEALTH_CHECK == *"ok"* ]]; then
    echo -e "${GREEN}✅ Health check passed!${NC}"
    echo "Response: $HEALTH_CHECK"
else
    echo -e "${RED}❌ Health check failed!${NC}"
    echo "Response: $HEALTH_CHECK"
fi
echo ""

echo "📝 Next steps:"
echo "1. Check logs: pm2 logs oldies-api"
echo "2. Test from external: curl http://16.171.208.249:5000/health"
echo "3. Seed database: curl http://16.171.208.249:5000/api/dev/seed"
echo ""

echo "🎉 Done!"
