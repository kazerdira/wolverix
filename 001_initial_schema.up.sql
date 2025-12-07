-- Werewolf Voice Game - Initial Database Schema
-- Production-ready PostgreSQL schema with proper constraints, indexes, and relationships

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- USER MANAGEMENT
-- ============================================================================

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(30) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    avatar_url VARCHAR(500),
    display_name VARCHAR(50),
    language VARCHAR(5) DEFAULT 'en',
    reputation_score INTEGER DEFAULT 100,
    is_banned BOOLEAN DEFAULT FALSE,
    banned_until TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP,
    
    CONSTRAINT username_length CHECK (char_length(username) >= 3),
    CONSTRAINT reputation_range CHECK (reputation_score >= 0 AND reputation_score <= 10000)
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_last_seen ON users(last_seen_at DESC);

-- User statistics
CREATE TABLE user_stats (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    total_games INTEGER DEFAULT 0,
    total_wins INTEGER DEFAULT 0,
    total_losses INTEGER DEFAULT 0,
    games_as_villager INTEGER DEFAULT 0,
    games_as_werewolf INTEGER DEFAULT 0,
    games_as_seer INTEGER DEFAULT 0,
    games_as_witch INTEGER DEFAULT 0,
    games_as_hunter INTEGER DEFAULT 0,
    villager_wins INTEGER DEFAULT 0,
    werewolf_wins INTEGER DEFAULT 0,
    current_streak INTEGER DEFAULT 0,
    best_streak INTEGER DEFAULT 0,
    total_kills INTEGER DEFAULT 0,
    total_deaths INTEGER DEFAULT 0,
    mvp_count INTEGER DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_stats_wins ON user_stats(total_wins DESC);
CREATE INDEX idx_user_stats_mvp ON user_stats(mvp_count DESC);

-- Friendships
CREATE TABLE friendships (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending', -- pending, accepted, blocked
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT no_self_friend CHECK (user_id != friend_id),
    CONSTRAINT unique_friendship UNIQUE (user_id, friend_id)
);

CREATE INDEX idx_friendships_user ON friendships(user_id);
CREATE INDEX idx_friendships_friend ON friendships(friend_id);
CREATE INDEX idx_friendships_status ON friendships(status);

-- ============================================================================
-- ROOM MANAGEMENT
-- ============================================================================

CREATE TABLE rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_code VARCHAR(10) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    host_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'waiting', -- waiting, playing, finished
    is_private BOOLEAN DEFAULT FALSE,
    password_hash VARCHAR(255),
    max_players INTEGER NOT NULL DEFAULT 12,
    current_players INTEGER NOT NULL DEFAULT 0,
    language VARCHAR(5) DEFAULT 'en',
    
    -- Game configuration (stored as JSON for flexibility)
    config JSONB NOT NULL DEFAULT '{}',
    
    -- Voice channel info
    agora_channel_name VARCHAR(64) NOT NULL,
    agora_app_id VARCHAR(64),
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    finished_at TIMESTAMP,
    
    CONSTRAINT valid_max_players CHECK (max_players >= 6 AND max_players <= 24),
    CONSTRAINT valid_current_players CHECK (current_players >= 0 AND current_players <= max_players)
);

CREATE INDEX idx_rooms_status ON rooms(status);
CREATE INDEX idx_rooms_host ON rooms(host_user_id);
CREATE INDEX idx_rooms_code ON rooms(room_code);
CREATE INDEX idx_rooms_created ON rooms(created_at DESC);
CREATE INDEX idx_rooms_language ON rooms(language);

-- Room players (tracks who's in each room)
CREATE TABLE room_players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_ready BOOLEAN DEFAULT FALSE,
    is_host BOOLEAN DEFAULT FALSE,
    seat_position INTEGER,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMP,
    
    CONSTRAINT unique_room_player UNIQUE (room_id, user_id)
);

CREATE INDEX idx_room_players_room ON room_players(room_id);
CREATE INDEX idx_room_players_user ON room_players(user_id);

-- ============================================================================
-- GAME SESSION & STATE
-- ============================================================================

CREATE TABLE game_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'active', -- active, paused, finished
    current_phase VARCHAR(20) NOT NULL, -- night, day, voting, night_action
    phase_number INTEGER NOT NULL DEFAULT 1,
    day_number INTEGER NOT NULL DEFAULT 0,
    phase_started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    phase_ends_at TIMESTAMP,
    
    -- Game state (JSON for flexibility with different role combinations)
    state JSONB NOT NULL DEFAULT '{}',
    
    -- Win condition tracking
    werewolves_alive INTEGER NOT NULL DEFAULT 0,
    villagers_alive INTEGER NOT NULL DEFAULT 0,
    winning_team VARCHAR(20), -- werewolves, villagers, lovers, tanner
    
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    finished_at TIMESTAMP,
    
    CONSTRAINT valid_phase_number CHECK (phase_number > 0),
    CONSTRAINT valid_day_number CHECK (day_number >= 0)
);

CREATE INDEX idx_game_sessions_room ON game_sessions(room_id);
CREATE INDEX idx_game_sessions_status ON game_sessions(status);
CREATE INDEX idx_game_sessions_created ON game_sessions(created_at DESC);

-- Player roles and game participation
CREATE TABLE game_players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(30) NOT NULL, -- werewolf, villager, seer, witch, hunter, cupid, bodyguard, etc.
    team VARCHAR(20) NOT NULL, -- werewolves, villagers, neutral
    is_alive BOOLEAN DEFAULT TRUE,
    died_at_phase INTEGER,
    death_reason VARCHAR(50), -- werewolf_kill, lynched, poison, hunter_shot, lover_death
    
    -- Role-specific state (e.g., witch potions used, hunter shot, etc.)
    role_state JSONB DEFAULT '{}',
    
    -- Lover pairing (NULL if not a lover)
    lover_id UUID REFERENCES game_players(id) ON DELETE SET NULL,
    
    -- Voice channel assignment
    current_voice_channel VARCHAR(50) DEFAULT 'main', -- main, werewolf, dead, spectator
    
    seat_position INTEGER NOT NULL,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT unique_session_player UNIQUE (session_id, user_id)
);

CREATE INDEX idx_game_players_session ON game_players(session_id);
CREATE INDEX idx_game_players_user ON game_players(user_id);
CREATE INDEX idx_game_players_role ON game_players(role);
CREATE INDEX idx_game_players_alive ON game_players(is_alive);

-- Game actions (tracks every action taken during the game)
CREATE TABLE game_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES game_players(id) ON DELETE CASCADE,
    phase_number INTEGER NOT NULL,
    action_type VARCHAR(50) NOT NULL, -- werewolf_vote, seer_divine, witch_heal, witch_poison, vote_lynch, hunter_shoot
    target_player_id UUID REFERENCES game_players(id) ON DELETE SET NULL,
    action_data JSONB DEFAULT '{}',
    is_successful BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT valid_phase_number_action CHECK (phase_number > 0)
);

CREATE INDEX idx_game_actions_session ON game_actions(session_id);
CREATE INDEX idx_game_actions_player ON game_actions(player_id);
CREATE INDEX idx_game_actions_phase ON game_actions(session_id, phase_number);
CREATE INDEX idx_game_actions_type ON game_actions(action_type);
CREATE INDEX idx_game_actions_created ON game_actions(created_at DESC);

-- Game events (tracks narrative events - deaths, phase changes, etc.)
CREATE TABLE game_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    phase_number INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL, -- phase_change, player_death, role_reveal, game_end
    event_data JSONB NOT NULL DEFAULT '{}',
    is_public BOOLEAN DEFAULT TRUE, -- some events are hidden until revealed
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT valid_phase_number_event CHECK (phase_number > 0)
);

CREATE INDEX idx_game_events_session ON game_events(session_id);
CREATE INDEX idx_game_events_phase ON game_events(session_id, phase_number);
CREATE INDEX idx_game_events_type ON game_events(event_type);
CREATE INDEX idx_game_events_created ON game_events(created_at DESC);

-- ============================================================================
-- VOICE CHANNEL MANAGEMENT
-- ============================================================================

CREATE TABLE voice_channels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    channel_name VARCHAR(64) NOT NULL,
    channel_type VARCHAR(20) NOT NULL, -- main, werewolf, dead, spectator
    agora_channel_name VARCHAR(64) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    closed_at TIMESTAMP,
    
    CONSTRAINT unique_room_channel_type UNIQUE (room_id, channel_type)
);

CREATE INDEX idx_voice_channels_room ON voice_channels(room_id);
CREATE INDEX idx_voice_channels_type ON voice_channels(channel_type);

-- Voice channel participants (tracks who's in which voice channel)
CREATE TABLE voice_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    channel_id UUID NOT NULL REFERENCES voice_channels(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    is_muted BOOLEAN DEFAULT FALSE,
    is_speaking BOOLEAN DEFAULT FALSE,
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMP,
    
    CONSTRAINT unique_channel_participant UNIQUE (channel_id, user_id)
);

CREATE INDEX idx_voice_participants_channel ON voice_participants(channel_id);
CREATE INDEX idx_voice_participants_user ON voice_participants(user_id);

-- ============================================================================
-- REPORTS & MODERATION
-- ============================================================================

CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    room_id UUID REFERENCES rooms(id) ON DELETE SET NULL,
    session_id UUID REFERENCES game_sessions(id) ON DELETE SET NULL,
    reason VARCHAR(50) NOT NULL, -- toxic, cheating, harassment, afk, other
    description TEXT,
    status VARCHAR(20) DEFAULT 'pending', -- pending, reviewed, action_taken, dismissed
    reviewed_by UUID REFERENCES users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMP,
    action_taken VARCHAR(100),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT no_self_report CHECK (reporter_id != reported_user_id)
);

CREATE INDEX idx_reports_reporter ON reports(reporter_id);
CREATE INDEX idx_reports_reported ON reports(reported_user_id);
CREATE INDEX idx_reports_status ON reports(status);
CREATE INDEX idx_reports_created ON reports(created_at DESC);

-- ============================================================================
-- ACHIEVEMENTS & BADGES
-- ============================================================================

CREATE TABLE achievements (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    description TEXT NOT NULL,
    icon_url VARCHAR(500),
    category VARCHAR(30), -- gameplay, social, mastery
    points INTEGER DEFAULT 10,
    rarity VARCHAR(20), -- common, rare, epic, legendary
    requirement_data JSONB,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE user_achievements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    achievement_id VARCHAR(50) NOT NULL REFERENCES achievements(id) ON DELETE CASCADE,
    unlocked_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    session_id UUID REFERENCES game_sessions(id) ON DELETE SET NULL,
    
    CONSTRAINT unique_user_achievement UNIQUE (user_id, achievement_id)
);

CREATE INDEX idx_user_achievements_user ON user_achievements(user_id);
CREATE INDEX idx_user_achievements_achievement ON user_achievements(achievement_id);
CREATE INDEX idx_user_achievements_unlocked ON user_achievements(unlocked_at DESC);

-- ============================================================================
-- TRIGGERS FOR AUTOMATIC UPDATES
-- ============================================================================

-- Update updated_at timestamp automatically
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_rooms_updated_at BEFORE UPDATE ON rooms
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_game_sessions_updated_at BEFORE UPDATE ON game_sessions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_stats_updated_at BEFORE UPDATE ON user_stats
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- SAMPLE ACHIEVEMENTS DATA
-- ============================================================================

INSERT INTO achievements (id, name, description, category, points, rarity) VALUES
    ('first_blood', 'First Blood', 'Kill your first victim as a werewolf', 'gameplay', 10, 'common'),
    ('detective', 'Detective', 'Successfully divine 3 werewolves as Seer in one game', 'gameplay', 25, 'rare'),
    ('survivor', 'Survivor', 'Win as a villager without dying', 'gameplay', 15, 'common'),
    ('lone_wolf', 'Lone Wolf', 'Win as the last remaining werewolf', 'gameplay', 50, 'epic'),
    ('perfect_potion', 'Perfect Potion', 'Use both witch potions successfully in one game', 'gameplay', 30, 'rare'),
    ('marksman', 'Marksman', 'Kill a werewolf with your hunter shot', 'gameplay', 20, 'common'),
    ('social_butterfly', 'Social Butterfly', 'Play 10 games with friends', 'social', 25, 'rare'),
    ('veteran', 'Veteran', 'Play 100 games', 'mastery', 100, 'legendary'),
    ('win_streak_5', 'On Fire', 'Win 5 games in a row', 'mastery', 50, 'epic');

-- ============================================================================
-- VIEWS FOR COMMON QUERIES
-- ============================================================================

-- Active rooms view
CREATE VIEW active_rooms AS
SELECT 
    r.id,
    r.room_code,
    r.name,
    r.status,
    r.is_private,
    r.max_players,
    r.current_players,
    r.language,
    r.created_at,
    u.username as host_username,
    u.avatar_url as host_avatar
FROM rooms r
JOIN users u ON r.host_user_id = u.id
WHERE r.status IN ('waiting', 'playing')
ORDER BY r.created_at DESC;

-- Player statistics view
CREATE VIEW player_rankings AS
SELECT 
    u.id,
    u.username,
    u.avatar_url,
    u.reputation_score,
    s.total_games,
    s.total_wins,
    s.total_losses,
    CASE WHEN s.total_games > 0 
        THEN ROUND((s.total_wins::numeric / s.total_games::numeric) * 100, 2)
        ELSE 0 
    END as win_rate,
    s.mvp_count,
    s.current_streak,
    s.best_streak
FROM users u
LEFT JOIN user_stats s ON u.id = s.user_id
WHERE NOT u.is_banned
ORDER BY s.total_wins DESC, win_rate DESC;
