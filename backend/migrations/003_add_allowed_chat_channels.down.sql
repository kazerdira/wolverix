-- Remove allowed_chat_channels column from game_players table

DROP INDEX IF EXISTS idx_game_players_chat_channels;
ALTER TABLE game_players DROP COLUMN IF EXISTS allowed_chat_channels;
