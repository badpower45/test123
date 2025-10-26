# 🚨 AWS EC2 Database Connection Fix Guide

## Issue Summary
Your EC2 instance **cannot connect to Neon PostgreSQL** due to missing/incorrect DATABASE_URL configuration.

---

## ✅ What I Fixed Locally

1. **Updated `.env`** - Corrected DATABASE_URL with the connection string you provided
2. **Updated `ecosystem.config.js`** - Added DATABASE_URL to PM2 environment variables

---

## 🔧 Step-by-Step Fix on AWS EC2

### **Prerequisites**
- EC2 Instance: `16.171.208.249` (eu-north-1, Stockholm)
- Public DNS: `ec2-16-171-208-249.eu-north-1.compute.amazonaws.com`
- Your `.pem` key file for SSH access

---

### **Step 1: Connect to EC2 Server**

```bash
# From your Windows machine (PowerShell or Git Bash)
ssh -i "D:\mytest123.pem" ubuntu@16.171.208.249
```

**If SSH fails**, check:
- Security group allows port 22 from your IP
- .pem file has correct permissions: `icacls "D:\mytest123.pem" /reset`

---

### **Step 2: Navigate to Project Directory**

```bash
cd ~/oldies-server
# or wherever you deployed the project
# Common locations: ~/oldies, ~/oldies-server, ~/app
```

---

### **Step 3: Create/Update .env File**

```bash
# Create or edit .env file
nano .env
```

**Paste this EXACT content:**

```env
# Neon PostgreSQL Database Connection
DATABASE_URL=postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require

# Server Configuration
PORT=5000
NODE_ENV=production
```

**Save and exit:**
- Press `Ctrl + X`
- Press `Y` to confirm
- Press `Enter`

---

### **Step 4: Update ecosystem.config.js**

```bash
# Edit PM2 config
nano ecosystem.config.js
```

**Replace the entire file with:**

```javascript
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
```

**Save and exit** (Ctrl+X, Y, Enter)

---

### **Step 5: Verify Database Connection**

```bash
# Test the DATABASE_URL environment variable
node -e "require('dotenv').config(); console.log('DATABASE_URL:', process.env.DATABASE_URL.substring(0, 50) + '...');"
```

**Expected output:**
```
DATABASE_URL: postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-yo...
```

---

### **Step 6: Rebuild and Restart Server**

```bash
# Install any missing dependencies
npm install

# Rebuild TypeScript
npm run build

# Stop PM2 if running
pm2 stop oldies-api || true
pm2 delete oldies-api || true

# Start fresh with updated config
pm2 start ecosystem.config.js

# Save PM2 configuration
pm2 save

# Check status
pm2 status
```

---

### **Step 7: Verify Server is Working**

```bash
# Test health endpoint locally on EC2
curl http://localhost:5000/health

# Check logs for database connection
pm2 logs oldies-api --lines 50
```

**Expected log output:**
```
[db] Loaded env files: /home/ubuntu/oldies-server/.env
[db] DATABASE_URL detected (length: 139 )
```

---

### **Step 8: Test from Your Windows Machine**

**Open PowerShell and run:**

```powershell
# Test health endpoint
Invoke-RestMethod -Uri "http://16.171.208.249:5000/health"

# Test login
$body = @{
    employee_id = "EMP001"
    pin = "1234"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://16.171.208.249:5000/api/auth/login" -Method Post -Body $body -ContentType "application/json"
```

**Expected Response:**
```json
{
  "success": true,
  "employee": {
    "id": "EMP001",
    "fullName": "Ahmed Mohamed",
    "role": "employee",
    "branch": "MAADI"
  }
}
```

---

## 🔍 Troubleshooting

### **Problem 1: "Connection refused" or timeout**

**Check Security Groups:**
1. Go to AWS Console → EC2 → Security Groups
2. Select `sg-01ed9fdd8217c4e7d`
3. Verify Inbound Rules include:
   - Port 5000, TCP, Source: 0.0.0.0/0

**On EC2, check if port is listening:**
```bash
sudo netstat -tulpn | grep 5000
```

Should show:
```
tcp6   0   0 :::5000   :::*   LISTEN   12345/node
```

---

### **Problem 2: Database connection errors in logs**

**Check PM2 logs:**
```bash
pm2 logs oldies-api --lines 100 --err
```

**Common issues:**
- **"password authentication failed"** → Wrong password in DATABASE_URL
- **"connection timeout"** → Firewall blocking Neon (unlikely, but check VPC settings)
- **"database does not exist"** → Wrong database name (should be `neondb`)

**Test direct database connection:**
```bash
# Install psql if not available
sudo apt-get update
sudo apt-get install -y postgresql-client

# Test connection
psql "postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require"
```

---

### **Problem 3: PM2 not starting**

```bash
# Check PM2 status
pm2 status

# Restart PM2
pm2 restart oldies-api

# If build failed, check TypeScript errors
npm run build
```

---

### **Problem 4: Environment variables not loading**

```bash
# Verify .env file exists and is readable
cat .env

# Check file permissions
ls -la .env

# Should be: -rw-r--r--
# If not, fix permissions:
chmod 644 .env
```

---

## 🎯 Quick Verification Checklist

- [ ] SSH into EC2 server successfully
- [ ] `.env` file exists in project root with correct DATABASE_URL
- [ ] `ecosystem.config.js` has DATABASE_URL in env section
- [ ] `npm run build` completes without errors
- [ ] PM2 shows status as "online" (not "errored")
- [ ] `curl http://localhost:5000/health` returns `{"status":"ok"}`
- [ ] Can access `http://16.171.208.249:5000/health` from Windows
- [ ] Login API works from Flutter app

---

## 📝 Additional Notes

### **Database Connection String Components**

```
postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require
```

- **User:** `neondb_owner`
- **Password:** `npg_D25sTdkbJxjf`
- **Host:** `ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech`
- **Database:** `neondb`
- **SSL:** Required

### **Important Security Note**

⚠️ Your database password is now visible in:
1. This markdown file
2. `.env` file
3. `ecosystem.config.js`

**For production, consider:**
- Using AWS Secrets Manager
- Rotating the Neon database password
- Restricting Neon IP whitelist to EC2's IP

---

## 🚀 Next Steps After Fix

1. **Seed Database** (if not already done):
   ```bash
   curl http://16.171.208.249:5000/api/dev/seed
   ```

2. **Update Flutter App** `lib/constants/api_endpoints.dart`:
   ```dart
   const String API_BASE_URL = 'http://16.171.208.249:5000/api';
   const String ROOT_BASE_URL = 'http://16.171.208.249:5000';
   ```

3. **Test Complete Flow:**
   - Login with EMP001 / 1234
   - Check-in
   - Send pulses
   - Check-out

---

## 📞 If Still Not Working

**Collect diagnostic information:**

```bash
# 1. PM2 status
pm2 status

# 2. Last 100 log lines
pm2 logs oldies-api --lines 100 --nostream > ~/debug.log

# 3. Environment check
echo "=== ENV CHECK ===" >> ~/debug.log
env | grep -E '(DATABASE|PORT|NODE_ENV)' >> ~/debug.log

# 4. Network check
echo "=== NETWORK CHECK ===" >> ~/debug.log
sudo netstat -tulpn | grep 5000 >> ~/debug.log

# 5. Download debug log
cat ~/debug.log
```

Copy the output and share for further debugging.

---

**Good luck! 🎉**
