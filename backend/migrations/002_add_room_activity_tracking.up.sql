-- Add activity tracking and timeout fields to rooms table
ALTER TABLE rooms ADD COLUMN last_activity_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();
ALTER TABLE rooms ADD COLUMN timeout_warning_sent BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE rooms ADD COLUMN timeout_extended_count INTEGER NOT NULL DEFAULT 0;

-- Update existing rooms to have last_activity_at = created_at
UPDATE rooms SET last_activity_at = created_at WHERE last_activity_at IS NULL;

-- Add index for efficient cleanup queries
CREATE INDEX idx_rooms_status_activity ON rooms(status, last_activity_at);
CREATE INDEX idx_rooms_cleanup ON rooms(status, created_at) WHERE status IN ('abandoned', 'completed');

-- Add comment for documentation
COMMENT ON COLUMN rooms.last_activity_at IS 'Timestamp of last meaningful activity (join, ready, settings change)';
COMMENT ON COLUMN rooms.timeout_warning_sent IS 'Whether 5-minute warning was sent before timeout';
COMMENT ON COLUMN rooms.timeout_extended_count IS 'Number of times host extended room timeout';
