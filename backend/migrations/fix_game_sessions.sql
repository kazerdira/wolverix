-- Fix game_sessions table to add missing columns
-- Run this if you already have a database and don't want to recreate it

-- Add missing columns
ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'active' 
    CHECK (status IN ('active', 'paused', 'completed', 'abandoned'));

ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS phase_started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS phase_ends_at TIMESTAMP WITH TIME ZONE;

ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS werewolves_alive INTEGER DEFAULT 0;

ALTER TABLE game_sessions ADD COLUMN IF NOT EXISTS villagers_alive INTEGER DEFAULT 0;

-- Create missing indexes
CREATE INDEX IF NOT EXISTS idx_game_sessions_status ON game_sessions(status);

CREATE INDEX IF NOT EXISTS idx_game_sessions_phase_ends ON game_sessions(phase_ends_at) 
    WHERE phase_ends_at IS NOT NULL;

-- Remove old column if it exists
ALTER TABLE game_sessions DROP COLUMN IF EXISTS phase_end_time;
