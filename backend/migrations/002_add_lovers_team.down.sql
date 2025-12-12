-- Revert to original team constraint
ALTER TABLE game_players DROP CONSTRAINT IF EXISTS game_players_team_check;
ALTER TABLE game_players ADD CONSTRAINT game_players_team_check 
    CHECK (team IN ('werewolves', 'villagers', 'neutral'));
