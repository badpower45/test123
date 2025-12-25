-- Enable Realtime for request tables

-- Enable Realtime replication for leave_requests
ALTER PUBLICATION supabase_realtime ADD TABLE leave_requests;

-- Enable Realtime replication for salary_advances
ALTER PUBLICATION supabase_realtime ADD TABLE salary_advances;

-- Enable Realtime replication for attendance_requests
ALTER PUBLICATION supabase_realtime ADD TABLE attendance_requests;

-- Verify
SELECT schemaname, tablename 
FROM pg_publication_tables 
WHERE pubname = 'supabase_realtime'
  AND tablename IN ('leave_requests', 'salary_advances', 'attendance_requests');
