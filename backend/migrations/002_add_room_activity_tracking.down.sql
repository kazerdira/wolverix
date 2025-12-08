-- Remove activity tracking and timeout fields from rooms table
DROP INDEX IF EXISTS idx_rooms_cleanup;
DROP INDEX IF EXISTS idx_rooms_status_activity;

ALTER TABLE rooms DROP COLUMN IF EXISTS timeout_extended_count;
ALTER TABLE rooms DROP COLUMN IF EXISTS timeout_warning_sent;
ALTER TABLE rooms DROP COLUMN IF EXISTS last_activity_at;
