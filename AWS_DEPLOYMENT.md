# AWS EC2 Deployment Guide - Oldies Workers API

## 📋 Prerequisites
- EC2 Instance: `16.171.208.249` (Ubuntu 24.04)
- Security Group: Port 5000 open for inbound traffic
- Neon PostgreSQL Database URL

---

## 🚀 Step 1: Install Node.js on EC2

```bash
# SSH into your server
ssh -i "D:\mytest123.pem" ubuntu@16.171.208.249

# Install Node.js 20.x LTS
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version  # Should show v20.x.x
npm --version

# Install PM2 globally
sudo npm install -g pm2
```

---

## 📦 Step 2: Upload Project Files

### Option A: Using SCP (from your Windows machine)

```powershell
# Navigate to project directory
cd "D:\Coding\project important\test123 (6)\test123"

# Create a deployment package (exclude node_modules, build, etc.)
# Upload essential files
scp -i "D:\mytest123.pem" -r server shared package.json tsconfig.json ecosystem.config.js ubuntu@16.171.208.249:~/oldies-server/
```

### Option B: Using Git (recommended)

```bash
# On EC2 server
cd ~
git clone <your-repo-url> oldies-server
cd oldies-server
```

---

## ⚙️ Step 3: Configure Environment

```bash
# On EC2 server
cd ~/oldies-server

# Create .env file
nano .env
```

**Add this content to .env:**

```env
DATABASE_URL=postgresql://neondb_owner:YOUR_PASSWORD@ep-floral-unit-a2rkt4s5.eu-central-1.aws.neon.tech/neondb?sslmode=require
PORT=5000
NODE_ENV=production
```

**Save and exit** (Ctrl+X, Y, Enter)

---

## 🔨 Step 4: Install Dependencies & Build

```bash
cd ~/oldies-server

# Install dependencies
npm install

# Build TypeScript
npm run build

# Verify build succeeded
ls -la dist/server/
```

---

## 🚀 Step 5: Start Server with PM2

```bash
# Create logs directory
mkdir -p logs

# Start with PM2
pm2 start ecosystem.config.js

# Check status
pm2 status

# View logs
pm2 logs oldies-api

# Save PM2 config
pm2 save

# Setup PM2 to start on boot
pm2 startup
# Run the command it gives you (with sudo)
```

---

## 🔓 Step 6: Configure AWS Security Group

1. Go to **AWS Console** → **EC2** → **Security Groups**
2. Find your instance's security group
3. **Add Inbound Rule:**
   - Type: Custom TCP
   - Port: 5000
   - Source: 0.0.0.0/0 (or your IP for security)
   - Description: Oldies API

---

## ✅ Step 7: Test Deployment

```bash
# On EC2 server - test locally
curl http://localhost:5000/health

# Seed database
curl http://localhost:5000/api/dev/seed

# Test login
curl -X POST http://localhost:5000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"employee_id":"EMP001","pin":"1234"}'
```

**From your local machine:**

```powershell
# Test from Windows
irm http://16.171.208.249:5000/health

# Seed database
irm http://16.171.208.249:5000/api/dev/seed

# Test login
$body = @{ employee_id = "EMP001"; pin = "1234" } | ConvertTo-Json
irm http://16.171.208.249:5000/api/auth/login -Method Post -Body $body -ContentType "application/json"
```

---

## 📱 Step 8: Update Flutter App

Update `lib/constants/api_endpoints.dart`:

```dart
// استخدم localhost للتطوير المحلي أو IP الجهاز للاختبار على أجهزة أخرى
const String API_BASE_URL = 'http://16.171.208.249:5000/api';
const String ROOT_BASE_URL = 'http://16.171.208.249:5000';
```

---

## 🛠️ Useful PM2 Commands

```bash
# View logs
pm2 logs oldies-api

# Restart server
pm2 restart oldies-api

# Stop server
pm2 stop oldies-api

# View CPU/Memory usage
pm2 monit

# Delete from PM2
pm2 delete oldies-api
```

---

## 🐛 Troubleshooting

### Port 5000 not accessible
```bash
# Check if server is running
pm2 status

# Check if port is listening
sudo netstat -tulpn | grep 5000

# Check firewall
sudo ufw status
```

### Database connection issues
```bash
# Test database connection
cd ~/oldies-server
node -e "require('dotenv').config(); console.log(process.env.DATABASE_URL);"
```

### View server logs
```bash
pm2 logs oldies-api --lines 100
```

---

## 🔐 Security Recommendations

1. **Use Environment Variables:** Never commit `.env` file
2. **Setup HTTPS:** Use nginx + Let's Encrypt for production
3. **Firewall:** Restrict port 5000 to specific IPs if possible
4. **Database:** Use strong password and enable SSL

---

## 📊 Monitoring

```bash
# Setup PM2 monitoring (optional)
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 10M
pm2 set pm2-logrotate:retain 7
```

---

**Your API will be available at:**
- Health: http://16.171.208.249:5000/health
- Login: http://16.171.208.249:5000/api/auth/login
- Seed: http://16.171.208.249:5000/api/dev/seed
