package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Server   ServerConfig
	Database DatabaseConfig
	Redis    RedisConfig
	JWT      JWTConfig
	Agora    AgoraConfig
}

type ServerConfig struct {
	Address        string
	Environment    string
	AllowedOrigins []string
}

type DatabaseConfig struct {
	Host     string
	Port     int
	User     string
	Password string
	DBName   string
	SSLMode  string
}

type RedisConfig struct {
	Address  string
	Password string
	DB       int
}

type JWTConfig struct {
	Secret            string
	ExpiryHours       int
	RefreshExpiryDays int
}

type AgoraConfig struct {
	AppID          string
	AppCertificate string
	TokenExpiry    uint32
}

func Load() (*Config, error) {
	cfg := &Config{
		Server: ServerConfig{
			Address:        getEnv("SERVER_ADDRESS", ":8080"),
			Environment:    getEnv("ENVIRONMENT", "development"),
			AllowedOrigins: strings.Split(getEnv("ALLOWED_ORIGINS", "*"), ","),
		},
		Database: DatabaseConfig{
			Host:     getEnv("DB_HOST", "localhost"),
			Port:     getEnvAsInt("DB_PORT", 5432),
			User:     getEnv("DB_USER", "postgres"),
			Password: getEnv("DB_PASSWORD", "postgres"),
			DBName:   getEnv("DB_NAME", "werewolf_voice"),
			SSLMode:  getEnv("DB_SSL_MODE", "disable"),
		},
		Redis: RedisConfig{
			Address:  getEnv("REDIS_ADDRESS", "localhost:6379"),
			Password: getEnv("REDIS_PASSWORD", ""),
			DB:       getEnvAsInt("REDIS_DB", 0),
		},
		JWT: JWTConfig{
			Secret:            getEnv("JWT_SECRET", "your-secret-key-change-in-production"),
			ExpiryHours:       getEnvAsInt("JWT_EXPIRY_HOURS", 24),
			RefreshExpiryDays: getEnvAsInt("JWT_REFRESH_EXPIRY_DAYS", 7),
		},
		Agora: AgoraConfig{
			AppID:          getEnv("AGORA_APP_ID", ""),
			AppCertificate: getEnv("AGORA_APP_CERTIFICATE", ""),
			TokenExpiry:    uint32(getEnvAsInt("AGORA_TOKEN_EXPIRY", 3600)),
		},
	}

	// Validate required fields (only in production)
	if cfg.Server.Environment == "production" {
		if cfg.Agora.AppID == "" {
			return nil, fmt.Errorf("AGORA_APP_ID is required in production")
		}
		if cfg.Agora.AppCertificate == "" {
			return nil, fmt.Errorf("AGORA_APP_CERTIFICATE is required in production")
		}
	}

	return cfg, nil
}

func (c *DatabaseConfig) ConnectionString() string {
	return fmt.Sprintf(
		"postgres://%s:%s@%s:%d/%s?sslmode=%s",
		c.User, c.Password, c.Host, c.Port, c.DBName, c.SSLMode,
	)
}

func getEnv(key, defaultValue string) string {
	if value, exists := os.LookupEnv(key); exists {
		return value
	}
	return defaultValue
}

func getEnvAsInt(key string, defaultValue int) int {
	if value, exists := os.LookupEnv(key); exists {
		if intValue, err := strconv.Atoi(value); err == nil {
			return intValue
		}
	}
	return defaultValue
}
