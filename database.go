package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"
	"github.com/yourusername/werewolf-voice/internal/config"
)

type Database struct {
	PG    *pgxpool.Pool
	Redis *redis.Client
}

// NewDatabase creates a new database connection
func NewDatabase(cfg *config.Config) (*Database, error) {
	// PostgreSQL connection
	pgConfig, err := pgxpool.ParseConfig(cfg.Database.GetDSN())
	if err != nil {
		return nil, fmt.Errorf("failed to parse database config: %w", err)
	}

	pgConfig.MaxConns = int32(cfg.Database.MaxConns)
	pgConfig.MinConns = int32(cfg.Database.MinConns)
	pgConfig.MaxConnLifetime = 1 * time.Hour
	pgConfig.MaxConnIdleTime = 30 * time.Minute

	pool, err := pgxpool.NewWithConfig(context.Background(), pgConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to create connection pool: %w", err)
	}

	// Test connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	
	if err := pool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Redis connection
	redisClient := redis.NewClient(&redis.Options{
		Addr:         cfg.Redis.GetAddr(),
		Password:     cfg.Redis.Password,
		DB:           cfg.Redis.DB,
		DialTimeout:  5 * time.Second,
		ReadTimeout:  3 * time.Second,
		WriteTimeout: 3 * time.Second,
		PoolSize:     10,
		MinIdleConns: 5,
	})

	// Test Redis connection
	if err := redisClient.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	return &Database{
		PG:    pool,
		Redis: redisClient,
	}, nil
}

// Close closes all database connections
func (db *Database) Close() {
	if db.PG != nil {
		db.PG.Close()
	}
	if db.Redis != nil {
		db.Redis.Close()
	}
}

// Health checks database health
func (db *Database) Health(ctx context.Context) error {
	if err := db.PG.Ping(ctx); err != nil {
		return fmt.Errorf("postgres unhealthy: %w", err)
	}
	if err := db.Redis.Ping(ctx).Err(); err != nil {
		return fmt.Errorf("redis unhealthy: %w", err)
	}
	return nil
}
