-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================================================
-- USERS TABLE
-- ============================================================================
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    avatar_url TEXT,
    language VARCHAR(10) DEFAULT 'en',
    is_online BOOLEAN DEFAULT false,
    last_seen_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_is_online ON users(is_online);

-- ============================================================================
-- USER STATS TABLE
-- ============================================================================
CREATE TABLE user_stats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    games_played INTEGER DEFAULT 0,
    games_won INTEGER DEFAULT 0,
    games_lost INTEGER DEFAULT 0,
    games_as_werewolf INTEGER DEFAULT 0,
    games_won_as_werewolf INTEGER DEFAULT 0,
    games_as_villager INTEGER DEFAULT 0,
    games_won_as_villager INTEGER DEFAULT 0,
    games_as_seer INTEGER DEFAULT 0,
    games_as_witch INTEGER DEFAULT 0,
    games_as_hunter INTEGER DEFAULT 0,
    games_as_cupid INTEGER DEFAULT 0,
    games_as_bodyguard INTEGER DEFAULT 0,
    total_kills INTEGER DEFAULT 0,
    total_saves INTEGER DEFAULT 0,
    total_correct_divinations INTEGER DEFAULT 0,
    longest_survival INTEGER DEFAULT 0,
    favorite_role VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id)
);

CREATE INDEX idx_user_stats_user_id ON user_stats(user_id);
CREATE INDEX idx_user_stats_games_played ON user_stats(games_played DESC);

-- ============================================================================
-- ROOMS TABLE
-- ============================================================================
CREATE TABLE rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_code VARCHAR(10) UNIQUE NOT NULL,
    name VARCHAR(100) NOT NULL,
    host_user_id UUID NOT NULL REFERENCES users(id),
    status VARCHAR(20) DEFAULT 'waiting' CHECK (status IN ('waiting', 'starting', 'playing', 'paused', 'finished')),
    is_private BOOLEAN DEFAULT false,
    password_hash VARCHAR(255),
    max_players INTEGER DEFAULT 12 CHECK (max_players >= 5 AND max_players <= 20),
    current_players INTEGER DEFAULT 0,
    language VARCHAR(10) DEFAULT 'en',
    config JSONB DEFAULT '{}'::jsonb,
    agora_channel_name VARCHAR(100),
    agora_app_id VARCHAR(50),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    started_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_rooms_room_code ON rooms(room_code);
CREATE INDEX idx_rooms_status ON rooms(status);
CREATE INDEX idx_rooms_host ON rooms(host_user_id);
CREATE INDEX idx_rooms_created_at ON rooms(created_at DESC);

-- ============================================================================
-- ROOM PLAYERS TABLE
-- ============================================================================
CREATE TABLE room_players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    is_ready BOOLEAN DEFAULT false,
    is_host BOOLEAN DEFAULT false,
    seat_position INTEGER,
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    left_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_room_players_room ON room_players(room_id);
CREATE INDEX idx_room_players_user ON room_players(user_id);
CREATE UNIQUE INDEX idx_room_players_active ON room_players(room_id, user_id) WHERE left_at IS NULL;

-- ============================================================================
-- GAME SESSIONS TABLE
-- ============================================================================
CREATE TABLE game_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(id),
    current_phase VARCHAR(30) DEFAULT 'night_0' CHECK (current_phase IN (
        'night_0', 'cupid_phase', 'werewolf_phase', 'seer_phase', 
        'witch_phase', 'bodyguard_phase', 'day_discussion', 
        'day_voting', 'defense_phase', 'final_vote', 'hunter_phase',
        'mayor_reveal', 'game_over'
    )),
    phase_number INTEGER DEFAULT 0,
    day_number INTEGER DEFAULT 0,
    phase_end_time TIMESTAMP WITH TIME ZONE,
    winner VARCHAR(20) CHECK (winner IN ('werewolves', 'villagers', 'lovers', 'tanner')),
    state JSONB DEFAULT '{}'::jsonb,
    config JSONB DEFAULT '{}'::jsonb,
    started_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ended_at TIMESTAMP WITH TIME ZONE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_game_sessions_room ON game_sessions(room_id);
CREATE INDEX idx_game_sessions_phase ON game_sessions(current_phase);
CREATE INDEX idx_game_sessions_started ON game_sessions(started_at DESC);

-- ============================================================================
-- GAME PLAYERS TABLE
-- ============================================================================
CREATE TABLE game_players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id),
    role VARCHAR(30) NOT NULL CHECK (role IN (
        'werewolf', 'villager', 'seer', 'witch', 'hunter', 
        'cupid', 'bodyguard', 'mayor', 'medium', 'tanner', 'little_girl'
    )),
    team VARCHAR(20) NOT NULL CHECK (team IN ('werewolves', 'villagers', 'neutral')),
    is_alive BOOLEAN DEFAULT true,
    died_at_phase INTEGER,
    death_reason VARCHAR(50),
    has_used_heal BOOLEAN DEFAULT false,
    has_used_poison BOOLEAN DEFAULT false,
    has_shot BOOLEAN DEFAULT false,
    is_protected BOOLEAN DEFAULT false,
    is_mayor BOOLEAN DEFAULT false,
    lover_id UUID REFERENCES game_players(id),
    current_voice_channel VARCHAR(50),
    seat_position INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_game_players_session ON game_players(session_id);
CREATE INDEX idx_game_players_user ON game_players(user_id);
CREATE INDEX idx_game_players_role ON game_players(role);
CREATE INDEX idx_game_players_alive ON game_players(session_id, is_alive);
CREATE INDEX idx_game_players_lover ON game_players(lover_id);

-- ============================================================================
-- GAME ACTIONS TABLE
-- ============================================================================
CREATE TABLE game_actions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES game_players(id),
    action_type VARCHAR(30) NOT NULL CHECK (action_type IN (
        'werewolf_vote', 'seer_divine', 'witch_heal', 'witch_poison',
        'bodyguard_protect', 'cupid_choose', 'lynch_vote', 'hunter_shoot',
        'mayor_reveal', 'defense_speech', 'medium_contact'
    )),
    target_player_id UUID REFERENCES game_players(id),
    secondary_target_id UUID REFERENCES game_players(id),
    phase_number INTEGER NOT NULL,
    action_data JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_game_actions_session ON game_actions(session_id);
CREATE INDEX idx_game_actions_player ON game_actions(player_id);
CREATE INDEX idx_game_actions_phase ON game_actions(session_id, phase_number);
CREATE INDEX idx_game_actions_type ON game_actions(action_type);

-- ============================================================================
-- GAME EVENTS TABLE
-- ============================================================================
CREATE TABLE game_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES game_sessions(id) ON DELETE CASCADE,
    phase_number INTEGER NOT NULL,
    event_type VARCHAR(50) NOT NULL CHECK (event_type IN (
        'game_started', 'phase_changed', 'player_killed', 'player_lynched',
        'no_lynch', 'role_revealed', 'lovers_revealed', 'seer_result',
        'witch_action', 'hunter_shot', 'mayor_elected', 'vote_cast',
        'game_ended', 'discussion_started', 'defense_started', 'message'
    )),
    event_data JSONB DEFAULT '{}'::jsonb,
    is_public BOOLEAN DEFAULT false,
    visible_to_roles TEXT[] DEFAULT '{}',
    visible_to_players UUID[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_game_events_session ON game_events(session_id);
CREATE INDEX idx_game_events_phase ON game_events(session_id, phase_number);
CREATE INDEX idx_game_events_type ON game_events(event_type);
CREATE INDEX idx_game_events_public ON game_events(session_id, is_public);

-- ============================================================================
-- VOICE CHANNELS TABLE
-- ============================================================================
CREATE TABLE voice_channels (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
    channel_name VARCHAR(100) NOT NULL,
    channel_type VARCHAR(30) DEFAULT 'main' CHECK (channel_type IN (
        'main', 'werewolf', 'dead', 'private'
    )),
    is_active BOOLEAN DEFAULT true,
    agora_channel_name VARCHAR(100),
    allowed_roles TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_voice_channels_room ON voice_channels(room_id);
CREATE INDEX idx_voice_channels_type ON voice_channels(channel_type);

-- ============================================================================
-- REFRESH TOKENS TABLE
-- ============================================================================
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    revoked_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_refresh_tokens_user ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_hash ON refresh_tokens(token_hash);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);

-- ============================================================================
-- TRIGGER FUNCTIONS
-- ============================================================================

-- Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to all relevant tables
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_stats_updated_at
    BEFORE UPDATE ON user_stats
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_rooms_updated_at
    BEFORE UPDATE ON rooms
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_game_sessions_updated_at
    BEFORE UPDATE ON game_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_game_players_updated_at
    BEFORE UPDATE ON game_players
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- CREATE DEFAULT USER STATS TRIGGER
-- ============================================================================
CREATE OR REPLACE FUNCTION create_user_stats()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO user_stats (user_id) VALUES (NEW.id);
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER create_user_stats_after_insert
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION create_user_stats();
