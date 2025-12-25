# Session Validation Action - Edge Function

## 📋 Description
Edge Function for processing session validation requests in the attendance system. This function is called when a manager approves or rejects an employee's session validation request.

## 🔧 Functionality

### Input Parameters
```json
{
  "request_id": "uuid-of-request",
  "action": "approve" | "reject",
  "manager_notes": "Optional notes from manager"
}
```

### Process Flow

1. **Validate Input**
   - Check required fields
   - Validate action type

2. **Fetch Request**
   - Get validation request details
   - Check if already processed

3. **Create Pulses**
   - Calculate pulse timestamps (every 5 minutes)
   - Create TRUE pulses if approved
   - Create FALSE pulses if rejected

4. **Update Request**
   - Set status to approved/rejected
   - Save manager notes
   - Set response timestamp

5. **Update Attendance** (if approved)
   - Update check_in_time to gap_start_time

### Output
```json
{
  "success": true,
  "action": "approve",
  "pulses_created": 3,
  "message": "Session validation approved successfully"
}
```

## 🚀 Deployment

### Prerequisites
- Supabase CLI installed: `npm install -g supabase`
- Logged in: `supabase login`

### Deploy Command
```bash
supabase functions deploy session-validation-action
```

### Or use the deployment script
```bash
# Linux/Mac
./deploy_session_validation.sh

# Windows
.\deploy_session_validation.ps1
```

## 🔐 Security

- Requires Authentication header
- Validates request ownership
- Prevents double-processing
- RLS policies enforced

## 📊 Examples

### Approve Request
```bash
curl -X POST 'https://your-project.supabase.co/functions/v1/session-validation-action' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "request_id": "123e4567-e89b-12d3-a456-426614174000",
    "action": "approve",
    "manager_notes": "Was in meeting"
  }'
```

### Reject Request
```bash
curl -X POST 'https://your-project.supabase.co/functions/v1/session-validation-action' \
  -H 'Authorization: Bearer YOUR_ANON_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "request_id": "123e4567-e89b-12d3-a456-426614174000",
    "action": "reject",
    "manager_notes": "Was not at branch"
  }'
```

## 🧪 Testing

### View Logs
```bash
supabase functions logs session-validation-action
```

### Test Locally
```bash
supabase functions serve session-validation-action
```

## 📝 Notes

- Pulses are created every 5 minutes starting from gap_start_time
- Last pulse is before gap_end_time
- Approved pulses have `inside_geofence: true`
- Rejected pulses have `inside_geofence: false`
- All created pulses have `created_by_validation: true`

## 🆘 Troubleshooting

### Function not found
- Ensure it's deployed: `supabase functions list`
- Redeploy: `supabase functions deploy session-validation-action`

### Authentication errors
- Check Authorization header
- Verify SUPABASE_ANON_KEY

### Request not found
- Check request_id exists
- Verify RLS policies

## 📞 Support
Check logs for detailed error messages:
```bash
supabase functions logs session-validation-action --tail
```
