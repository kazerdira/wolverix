-- Drop triggers first
DROP TRIGGER IF EXISTS create_user_stats_after_insert ON users;
DROP TRIGGER IF EXISTS update_game_players_updated_at ON game_players;
DROP TRIGGER IF EXISTS update_game_sessions_updated_at ON game_sessions;
DROP TRIGGER IF EXISTS update_rooms_updated_at ON rooms;
DROP TRIGGER IF EXISTS update_user_stats_updated_at ON user_stats;
DROP TRIGGER IF EXISTS update_users_updated_at ON users;

-- Drop functions
DROP FUNCTION IF EXISTS create_user_stats();
DROP FUNCTION IF EXISTS update_updated_at_column();

-- Drop tables in reverse dependency order
DROP TABLE IF EXISTS refresh_tokens;
DROP TABLE IF EXISTS voice_channels;
DROP TABLE IF EXISTS game_events;
DROP TABLE IF EXISTS game_actions;
DROP TABLE IF EXISTS game_players;
DROP TABLE IF EXISTS game_sessions;
DROP TABLE IF EXISTS room_players;
DROP TABLE IF EXISTS rooms;
DROP TABLE IF EXISTS user_stats;
DROP TABLE IF EXISTS users;

-- Drop extension (optional - usually keep it)
-- DROP EXTENSION IF EXISTS "uuid-ossp";
