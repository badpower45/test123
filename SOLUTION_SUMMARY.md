# 🎯 AWS EC2 Database Connection - Complete Solution Summary

## 📋 Problem Identified

Your Node.js server on AWS EC2 **cannot connect to Neon PostgreSQL database** due to:

1. **Missing `.env` file** on EC2 server
2. **Incomplete DATABASE_URL** in local .env (was truncated)
3. **Missing DATABASE_URL** in PM2 ecosystem.config.js

## ✅ What I Fixed in Your Local Codebase

### 1. Updated `.env`
```env
DATABASE_URL=postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require
PORT=5000
NODE_ENV=production
```

### 2. Updated `ecosystem.config.js`
Added `DATABASE_URL` to the PM2 environment configuration.

### 3. Created Helper Files
- `FIX_AWS_CONNECTION.md` - Complete step-by-step manual fix guide
- `aws-fix-database.sh` - Automated bash script for EC2
- `test-aws-connection.ps1` - PowerShell test script for Windows

---

## 🚀 Quick Fix (Choose One Method)

### **Method 1: Automated Script (Recommended)**

**Step 1:** SSH into your EC2 server
```bash
ssh -i "D:\mytest123.pem" ubuntu@16.171.208.249
```

**Step 2:** Create and run the fix script
```bash
cd ~/oldies-server

# Create the fix script
cat > fix.sh << 'SCRIPT_END'
#!/bin/bash
set -e

# Create .env
cat > .env << 'EOF'
DATABASE_URL=postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require
PORT=5000
NODE_ENV=production
EOF

# Update ecosystem.config.js
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

# Install and build
npm install
npm run build

# Restart PM2
mkdir -p logs
pm2 stop oldies-api || true
pm2 delete oldies-api || true
pm2 start ecosystem.config.js
pm2 save

echo "✅ Done! Testing health endpoint..."
sleep 2
curl http://localhost:5000/health
SCRIPT_END

# Make executable and run
chmod +x fix.sh
./fix.sh
```

---

### **Method 2: Manual Steps**

If you prefer manual control, follow **`FIX_AWS_CONNECTION.md`** step-by-step.

---

## 🧪 Testing the Fix

### **From EC2 Server (SSH)**

```bash
# Check PM2 status
pm2 status

# Test health endpoint
curl http://localhost:5000/health

# Check logs
pm2 logs oldies-api --lines 50

# Should see:
# [db] Loaded env files: /home/ubuntu/oldies-server/.env
# [db] DATABASE_URL detected (length: 139 )
```

### **From Your Windows Machine**

**Option A: PowerShell Script (Recommended)**
```powershell
cd "D:\Coding\project important\test123 (7)\test123"
.\test-aws-connection.ps1
```

**Option B: Manual Commands**
```powershell
# Test health
Invoke-RestMethod -Uri "http://16.171.208.249:5000/health"

# Test login
$body = @{ employee_id = "EMP001"; pin = "1234" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://16.171.208.249:5000/api/auth/login" -Method Post -Body $body -ContentType "application/json"
```

---

## 🔍 Verification Checklist

- [ ] **EC2 Instance Running** - Check AWS Console
- [ ] **Security Group Allows Port 5000** - Inbound rule for 0.0.0.0/0
- [ ] **`.env` file exists** - `cat ~/oldies-server/.env`
- [ ] **DATABASE_URL is set** - Should show connection string
- [ ] **PM2 status is "online"** - `pm2 status`
- [ ] **Health endpoint works locally** - `curl http://localhost:5000/health`
- [ ] **Health endpoint works externally** - From Windows browser/PowerShell
- [ ] **Database connection successful** - Check PM2 logs for "[db] DATABASE_URL detected"
- [ ] **Login API works** - Test with EMP001/1234

---

## 🐛 Common Issues & Solutions

### Issue 1: "Connection Timeout" from Windows

**Cause:** Security group not allowing port 5000

**Solution:**
1. AWS Console → EC2 → Security Groups
2. Select `sg-01ed9fdd8217c4e7d`
3. Edit Inbound Rules
4. Add: Type=Custom TCP, Port=5000, Source=0.0.0.0/0

### Issue 2: "ECONNREFUSED" in PM2 logs

**Cause:** Database connection string incorrect

**Solution:**
```bash
# Verify DATABASE_URL
cd ~/oldies-server
cat .env | grep DATABASE_URL

# Should show full connection string
# If not, recreate .env file
```

### Issue 3: PM2 shows "errored" status

**Cause:** Build failure or missing dependencies

**Solution:**
```bash
cd ~/oldies-server
npm install
npm run build
pm2 restart oldies-api
pm2 logs oldies-api --err
```

### Issue 4: "password authentication failed"

**Cause:** Wrong database password

**Solution:**
- Verify the password in Neon dashboard matches: `npg_D25sTdkbJxjf`
- If Neon password was changed, update .env and ecosystem.config.js

---

## 📊 Your AWS Configuration Summary

| Component | Value |
|-----------|-------|
| **EC2 Instance ID** | `i-0a77c4c0dfc196b95` |
| **Public IP** | `16.171.208.249` |
| **Private IP** | `172.31.39.49` |
| **Region** | `eu-north-1` (Stockholm) |
| **Instance Type** | `t3.micro` |
| **Security Group** | `sg-01ed9fdd8217c4e7d` |
| **VPC** | `vpc-073a0e83ecd2b059c` |
| **Subnet** | `subnet-0de902a9831f342f2` |
| **Open Ports** | 22 (SSH), 80 (HTTP), 443 (HTTPS), 5000 (API) |

| Database | Value |
|----------|-------|
| **Provider** | Neon PostgreSQL |
| **Host** | `ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech` |
| **Database** | `neondb` |
| **User** | `neondb_owner` |
| **Password** | `npg_D25sTdkbJxjf` |
| **Region** | `us-east-1` (AWS) |
| **SSL** | Required |

---

## 🎯 Next Steps After Fix

### 1. Seed Database (First Time Only)
```bash
curl http://16.171.208.249:5000/api/dev/seed
```

### 2. Update Flutter App

Edit `lib/constants/api_endpoints.dart`:
```dart
const String API_BASE_URL = 'http://16.171.208.249:5000/api';
const String ROOT_BASE_URL = 'http://16.171.208.249:5000';
```

### 3. Test Complete Flow
- Login with EMP001 / 1234
- Check-in
- Send location pulses
- Check-out
- View reports

### 4. Test Manager Dashboard
Open in browser:
```
http://16.171.208.249:5000/manager-dashboard.html
```

---

## 🔐 Security Recommendations

⚠️ **IMPORTANT:** Your database credentials are now exposed in:
- This document
- `.env` file
- `ecosystem.config.js`
- Git history (if committed)

### **For Production:**

1. **Rotate Neon Password**
   - Go to Neon dashboard
   - Change database password
   - Update .env and ecosystem.config.js

2. **Use AWS Secrets Manager**
   ```bash
   # Store secret
   aws secretsmanager create-secret --name oldies/db/url --secret-string "postgresql://..."
   
   # Retrieve in code
   const secret = await secretsManager.getSecretValue({ SecretId: 'oldies/db/url' }).promise();
   ```

3. **Restrict Security Group**
   - Change port 5000 source from `0.0.0.0/0` to specific IPs
   - Use AWS ALB/CloudFront for public access

4. **Enable HTTPS**
   - Setup nginx reverse proxy
   - Get SSL certificate from Let's Encrypt
   - Force HTTPS redirect

---

## 📞 Support Commands

### View Logs
```bash
# PM2 logs (real-time)
pm2 logs oldies-api

# PM2 logs (last 100 lines)
pm2 logs oldies-api --lines 100 --nostream

# Error logs only
pm2 logs oldies-api --err
```

### Restart Server
```bash
pm2 restart oldies-api
```

### Stop Server
```bash
pm2 stop oldies-api
```

### Monitor Resources
```bash
pm2 monit
```

### Delete and Recreate
```bash
pm2 delete oldies-api
pm2 start ecosystem.config.js
pm2 save
```

---

## 📚 Files Created for You

1. **`FIX_AWS_CONNECTION.md`** - Detailed manual fix guide (364 lines)
2. **`aws-fix-database.sh`** - Automated bash script for EC2 (153 lines)
3. **`test-aws-connection.ps1`** - PowerShell test script for Windows (121 lines)
4. **This file** - Complete solution summary

---

## ✅ Expected Final Result

After applying the fix, you should see:

**PM2 Status:**
```
┌────┬────────────┬──────────┬──────┬───────────┬──────────┐
│ id │ name       │ mode     │ ↺    │ status    │ cpu      │
├────┼────────────┼──────────┼──────┼───────────┼──────────┤
│ 0  │ oldies-api │ fork     │ 0    │ online    │ 0.3%     │
└────┴────────────┴──────────┴──────┴───────────┴──────────┘
```

**Health Check:**
```json
{
  "status": "ok",
  "message": "Oldies Workers API is running"
}
```

**Login Response:**
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

**Good luck! 🚀**

If you encounter any issues, check:
1. PM2 logs: `pm2 logs oldies-api`
2. This summary document
3. `FIX_AWS_CONNECTION.md` for detailed troubleshooting
