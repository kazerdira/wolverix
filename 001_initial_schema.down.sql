-- Rollback initial schema

DROP VIEW IF EXISTS player_rankings CASCADE;
DROP VIEW IF EXISTS active_rooms CASCADE;

DROP TRIGGER IF EXISTS update_user_stats_updated_at ON user_stats;
DROP TRIGGER IF EXISTS update_game_sessions_updated_at ON game_sessions;
DROP TRIGGER IF EXISTS update_rooms_updated_at ON rooms;
DROP TRIGGER IF EXISTS update_users_updated_at ON users;

DROP FUNCTION IF EXISTS update_updated_at_column CASCADE;

DROP TABLE IF EXISTS user_achievements CASCADE;
DROP TABLE IF EXISTS achievements CASCADE;
DROP TABLE IF EXISTS reports CASCADE;
DROP TABLE IF EXISTS voice_participants CASCADE;
DROP TABLE IF EXISTS voice_channels CASCADE;
DROP TABLE IF EXISTS game_events CASCADE;
DROP TABLE IF EXISTS game_actions CASCADE;
DROP TABLE IF EXISTS game_players CASCADE;
DROP TABLE IF EXISTS game_sessions CASCADE;
DROP TABLE IF EXISTS room_players CASCADE;
DROP TABLE IF EXISTS rooms CASCADE;
DROP TABLE IF EXISTS friendships CASCADE;
DROP TABLE IF EXISTS user_stats CASCADE;
DROP TABLE IF EXISTS users CASCADE;

DROP EXTENSION IF EXISTS "uuid-ossp";
