-- Migration: Set ON DELETE SET NULL for all manager/approver FKs
ALTER TABLE leave_requests
  ALTER COLUMN assigned_manager_id DROP NOT NULL,
  DROP CONSTRAINT IF EXISTS leave_requests_assigned_manager_id_fkey,
  ADD CONSTRAINT leave_requests_assigned_manager_id_fkey FOREIGN KEY (assigned_manager_id) REFERENCES employees(id) ON DELETE SET NULL;

ALTER TABLE salary_advances
  ALTER COLUMN assigned_manager_id DROP NOT NULL,
  DROP CONSTRAINT IF EXISTS salary_advances_assigned_manager_id_fkey,
  ADD CONSTRAINT salary_advances_assigned_manager_id_fkey FOREIGN KEY (assigned_manager_id) REFERENCES employees(id) ON DELETE SET NULL;

ALTER TABLE attendance_requests
  ALTER COLUMN assigned_manager_id DROP NOT NULL,
  DROP CONSTRAINT IF EXISTS attendance_requests_assigned_manager_id_fkey,
  ADD CONSTRAINT attendance_requests_assigned_manager_id_fkey FOREIGN KEY (assigned_manager_id) REFERENCES employees(id) ON DELETE SET NULL;

-- Add more as needed for other manager/approver FKs
