package database

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/kazerdira/wolverix/backend/internal/config"
	"github.com/redis/go-redis/v9"
)

type Database struct {
	PG    *pgxpool.Pool
	Redis *redis.Client
}

func NewDatabase(cfg *config.Config) (*Database, error) {
	// Connect to PostgreSQL
	pgConfig, err := pgxpool.ParseConfig(cfg.Database.ConnectionString())
	if err != nil {
		return nil, fmt.Errorf("failed to parse database config: %w", err)
	}

	// Connection pool settings
	pgConfig.MaxConns = 25
	pgConfig.MinConns = 5
	pgConfig.MaxConnLifetime = time.Hour
	pgConfig.MaxConnIdleTime = 30 * time.Minute
	pgConfig.HealthCheckPeriod = time.Minute

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	pgPool, err := pgxpool.NewWithConfig(ctx, pgConfig)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to PostgreSQL: %w", err)
	}

	// Test PostgreSQL connection
	if err := pgPool.Ping(ctx); err != nil {
		return nil, fmt.Errorf("failed to ping PostgreSQL: %w", err)
	}

	// Connect to Redis
	redisClient := redis.NewClient(&redis.Options{
		Addr:     cfg.Redis.Address,
		Password: cfg.Redis.Password,
		DB:       cfg.Redis.DB,
	})

	// Test Redis connection
	if err := redisClient.Ping(ctx).Err(); err != nil {
		return nil, fmt.Errorf("failed to connect to Redis: %w", err)
	}

	return &Database{
		PG:    pgPool,
		Redis: redisClient,
	}, nil
}

func (db *Database) Close() {
	if db.PG != nil {
		db.PG.Close()
	}
	if db.Redis != nil {
		db.Redis.Close()
	}
}

func (db *Database) Health(ctx context.Context) error {
	// Check PostgreSQL
	if err := db.PG.Ping(ctx); err != nil {
		return fmt.Errorf("postgresql unhealthy: %w", err)
	}

	// Check Redis
	if err := db.Redis.Ping(ctx).Err(); err != nil {
		return fmt.Errorf("redis unhealthy: %w", err)
	}

	return nil
}
