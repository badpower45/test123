-- Migration: Add managerId to branches table
ALTER TABLE branches ADD COLUMN manager_id TEXT REFERENCES employees(id);