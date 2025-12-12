-- Add allowed_chat_channels column to game_players table
-- This column tracks which chat channels each player can access during the game

ALTER TABLE game_players 
ADD COLUMN IF NOT EXISTS allowed_chat_channels TEXT[] DEFAULT '{}';

-- Add index for efficient querying
CREATE INDEX IF NOT EXISTS idx_game_players_chat_channels ON game_players USING GIN (allowed_chat_channels);
