-- Add branch_id column to pulses table
ALTER TABLE pulses 
ADD COLUMN IF NOT EXISTS branch_id UUID REFERENCES branches(id) ON DELETE CASCADE;

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_pulses_branch_id ON pulses(branch_id);
