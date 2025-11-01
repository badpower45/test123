#!/bin/bash
docker exec oldies-postgres psql -U postgres -d oldies -c "ALTER TYPE notification_type ADD VALUE 'LOCATION_WARNING';"
