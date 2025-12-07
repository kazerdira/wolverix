package config

import (
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/joho/godotenv"
)

type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Redis    RedisConfig
	Agora    AgoraConfig
	JWT      JWTConfig
	Game     GameConfig
}

type ServerConfig struct {
	Port            string
	Host            string
	Environment     string
	AllowedOrigins  []string
	ReadTimeout     time.Duration
	WriteTimeout    time.Duration
	ShutdownTimeout time.Duration
}

type DatabaseConfig struct {
	Host     string
	Port     int
	User     string
	Password string
	DBName   string
	SSLMode  string
	MaxConns int
	MinConns int
}

type RedisConfig struct {
	Host     string
	Port     int
	Password string
	DB       int
}

type AgoraConfig struct {
	AppID          string
	AppCertificate string
	TokenExpiry    uint32 // in seconds
}

type JWTConfig struct {
	Secret     string
	Expiry     time.Duration
	RefreshExp time.Duration
}

type GameConfig struct {
	MinPlayers        int
	MaxPlayers        int
	PhaseTimeoutDay   time.Duration
	PhaseTimeoutNight time.Duration
	VotingTimeout     time.Duration
	MaxRoomsPerUser   int
}

// Load loads configuration from environment variables
func Load() (*Config, error) {
	// Load .env file if exists (for local development)
	_ = godotenv.Load()

	cfg := &Config{
		Server: ServerConfig{
			Port:            getEnv("SERVER_PORT", "8080"),
			Host:            getEnv("SERVER_HOST", "0.0.0.0"),
			Environment:     getEnv("ENVIRONMENT", "development"),
			AllowedOrigins:  []string{getEnv("ALLOWED_ORIGINS", "*")},
			ReadTimeout:     getDurationEnv("SERVER_READ_TIMEOUT", 30*time.Second),
			WriteTimeout:    getDurationEnv("SERVER_WRITE_TIMEOUT", 30*time.Second),
			ShutdownTimeout: getDurationEnv("SERVER_SHUTDOWN_TIMEOUT", 10*time.Second),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getIntEnv("DB_PORT", 5432),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", "postgres"),
			DBName:   getEnv("DB_NAME", "werewolf_db"),
			SSLMode:  getEnv("DB_SSL_MODE", "disable"),
			MaxConns: getIntEnv("DB_MAX_CONNS", 25),
			MinConns: getIntEnv("DB_MIN_CONNS", 5),
		},
		Redis: RedisConfig{
			Host:     getEnv("REDIS_HOST", "localhost"),
			Port:     getIntEnv("REDIS_PORT", 6379),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getIntEnv("REDIS_DB", 0),
		},
		Agora: AgoraConfig{
			AppID:          mustGetEnv("AGORA_APP_ID"),
			AppCertificate: mustGetEnv("AGORA_APP_CERTIFICATE"),
			TokenExpiry:    uint32(getIntEnv("AGORA_TOKEN_EXPIRY", 3600)), // 1 hour default
		},
		JWT: JWTConfig{
			Secret:     mustGetEnv("JWT_SECRET"),
			Expiry:     getDurationEnv("JWT_EXPIRY", 24*time.Hour),
			RefreshExp: getDurationEnv("JWT_REFRESH_EXPIRY", 7*24*time.Hour),
		},
		Game: GameConfig{
			MinPlayers:        getIntEnv("GAME_MIN_PLAYERS", 6),
			MaxPlayers:        getIntEnv("GAME_MAX_PLAYERS", 24),
			PhaseTimeoutDay:   getDurationEnv("GAME_PHASE_TIMEOUT_DAY", 5*time.Minute),
			PhaseTimeoutNight: getDurationEnv("GAME_PHASE_TIMEOUT_NIGHT", 2*time.Minute),
			VotingTimeout:     getDurationEnv("GAME_VOTING_TIMEOUT", 1*time.Minute),
			MaxRoomsPerUser:   getIntEnv("GAME_MAX_ROOMS_PER_USER", 1),
		},
	}

	return cfg, cfg.Validate()
}

// Validate checks if all required configuration is present
func (c *Config) Validate() error {
	if c.Agora.AppID == "" {
		return fmt.Errorf("AGORA_APP_ID is required")
	}
	if c.Agora.AppCertificate == "" {
		return fmt.Errorf("AGORA_APP_CERTIFICATE is required")
	}
	if c.JWT.Secret == "" {
		return fmt.Errorf("JWT_SECRET is required")
	}
	if c.Database.Password == "" && c.Server.Environment == "production" {
		return fmt.Errorf("DB_PASSWORD is required in production")
	}
	return nil
}

// GetDSN returns PostgreSQL connection string
func (c *DatabaseConfig) GetDSN() string {
	return fmt.Sprintf(
		"host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
		c.Host, c.Port, c.User, c.Password, c.DBName, c.SSLMode,
	)
}

// GetRedisAddr returns Redis address
func (c *RedisConfig) GetAddr() string {
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}

// Helper functions
func getEnv(key, defaultValue string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return defaultValue
}

func mustGetEnv(key string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	panic(fmt.Sprintf("Environment variable %s is required", key))
}

func getIntEnv(key string, defaultValue int) int {
	if value := os.Getenv(key); value != "" {
		if intVal, err := strconv.Atoi(value); err == nil {
			return intVal
		}
	}
	return defaultValue
}

func getDurationEnv(key string, defaultValue time.Duration) time.Duration {
	if value := os.Getenv(key); value != "" {
		if duration, err := time.ParseDuration(value); err == nil {
			return duration
		}
	}
	return defaultValue
}
