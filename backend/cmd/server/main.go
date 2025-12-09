package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/gin-contrib/cors"
	"github.com/gin-gonic/gin"
	"github.com/joho/godotenv"
	"github.com/kazerdira/wolverix/backend/internal/agora"
	"github.com/kazerdira/wolverix/backend/internal/api"
	"github.com/kazerdira/wolverix/backend/internal/config"
	"github.com/kazerdira/wolverix/backend/internal/database"
	"github.com/kazerdira/wolverix/backend/internal/game"
	"github.com/kazerdira/wolverix/backend/internal/middleware"
	"github.com/kazerdira/wolverix/backend/internal/room"
	"github.com/kazerdira/wolverix/backend/internal/websocket"
)

func main() {
	// Load .env file (ignore error in production where env vars are set directly)
	// Try multiple paths to find .env file
	_ = godotenv.Load("../../.env")
	_ = godotenv.Load(".env")

	// Load configuration
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}

	// Initialize database
	db, err := database.NewDatabase(cfg)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}
	defer db.Close()

	log.Println("✓ Connected to database")

	// Initialize services
	gameEngine := game.NewEngine(db.PG)
	agoraService := agora.NewService(&cfg.Agora)
	wsHub := websocket.NewHub()

	// Start WebSocket hub
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go wsHub.Run(ctx)

	log.Println("✓ WebSocket hub started")

	// Start game scheduler
	scheduler := gameEngine.GetScheduler()
	scheduler.StartPhaseTimeoutChecker()

	// Reschedule any active games (useful for server restarts)
	if err := scheduler.RescheduleActiveSessions(ctx); err != nil {
		log.Printf("⚠️  Warning: Failed to reschedule active sessions: %v", err)
	} else {
		log.Println("✓ Game scheduler started")
	}

	// Initialize room lifecycle manager
	lifecycleManager := room.NewLifecycleManager(db, wsHub)
	go lifecycleManager.Start(ctx)

	// Initialize API handler
	handler := api.NewHandler(db, gameEngine, agoraService, wsHub, lifecycleManager)

	// Setup Gin router
	if cfg.Server.Environment == "production" {
		gin.SetMode(gin.ReleaseMode)
	}

	router := gin.Default()

	// CORS middleware
	router.Use(cors.New(cors.Config{
		AllowOrigins:     cfg.Server.AllowedOrigins,
		AllowMethods:     []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
		AllowHeaders:     []string{"Origin", "Content-Type", "Accept", "Authorization"},
		ExposeHeaders:    []string{"Content-Length"},
		AllowCredentials: true,
		MaxAge:           12 * time.Hour,
	}))

	// Health check
	router.GET("/health", func(c *gin.Context) {
		if err := db.Health(c.Request.Context()); err != nil {
			c.JSON(http.StatusServiceUnavailable, gin.H{"status": "unhealthy", "error": err.Error()})
			return
		}
		c.JSON(http.StatusOK, gin.H{"status": "healthy"})
	})

	// Public routes
	public := router.Group("/api/v1")
	{
		public.POST("/auth/register", handler.Register)
		public.POST("/auth/login", handler.Login)
		public.POST("/auth/refresh", handler.RefreshToken)
		public.GET("/rooms", handler.GetRooms)

		// WebSocket (handles auth via query param token)
		public.GET("/ws", handler.HandleWebSocket)
	}

	// Protected routes
	protected := router.Group("/api/v1")
	protected.Use(middleware.AuthMiddleware(cfg.JWT.Secret))
	{
		// User routes
		protected.GET("/users/me", handler.GetCurrentUser)
		protected.PUT("/users/me", handler.UpdateUser)
		protected.GET("/users/:userId/stats", handler.GetUserStats)

		// Room routes
		protected.POST("/rooms", handler.CreateRoom)
		protected.POST("/rooms/join", handler.JoinRoom)
		protected.GET("/rooms/:roomId", handler.GetRoom)
		protected.POST("/rooms/:roomId/start", handler.StartGame)
		protected.POST("/rooms/:roomId/leave", handler.LeaveRoom)
		protected.POST("/rooms/force-leave-all", handler.ForceLeaveAllRooms)
		protected.POST("/rooms/:roomId/ready", handler.SetReady)
		protected.POST("/rooms/:roomId/kick", handler.KickPlayer)
		protected.POST("/rooms/:roomId/extend-timeout", handler.ExtendRoomTimeout)
		protected.POST("/rooms/:roomId/extend", handler.ExtendRoomTimeout) // Alternative route for compatibility

		// Game routes
		protected.GET("/games/:sessionId", handler.GetGameState)
		protected.POST("/games/:sessionId/action", handler.PerformAction)
		protected.GET("/games/:sessionId/history", handler.GetGameHistory)

		// Agora token
		protected.POST("/agora/token", handler.GetAgoraToken)
	}

	// Create HTTP server
	server := &http.Server{
		Addr:         cfg.Server.Address,
		Handler:      router,
		ReadTimeout:  15 * time.Second,
		WriteTimeout: 15 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Start server in goroutine
	go func() {
		log.Printf("🚀 Server starting on %s", cfg.Server.Address)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server error: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	// Stop scheduler first
	scheduler.Stop()

	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer shutdownCancel()

	if err := server.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Server forced to shutdown: %v", err)
	}

	log.Println("Server exited gracefully")
}
