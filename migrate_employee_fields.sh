#!/bin/bash

echo "🔄 Starting migration..."
echo ""

# Get DATABASE_URL from PM2 environment
DATABASE_URL=$(pm2 describe oldies-api | grep -A 1 "DATABASE_URL" | tail -1 | awk '{print $NF}')

if [ -z "$DATABASE_URL" ]; then
    echo "❌ DATABASE_URL not found in PM2 environment"
    exit 1
fi

echo "Running migrations on database..."
echo ""

# Run migrations
psql "$DATABASE_URL" << 'EOF'
ALTER TABLE employees ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS birth_date DATE;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE employees ADD COLUMN IF NOT EXISTS phone TEXT;

-- Verify
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'employees' 
AND column_name IN ('address', 'birth_date', 'email', 'phone')
ORDER BY column_name;
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Migration completed successfully!"
else
    echo ""
    echo "❌ Migration failed!"
    exit 1
fi
