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
	"github.com/yourusername/werewolf-voice/internal/agora"
	"github.com/yourusername/werewolf-voice/internal/api"
	"github.com/yourusername/werewolf-voice/internal/config"
	"github.com/yourusername/werewolf-voice/internal/database"
	"github.com/yourusername/werewolf-voice/internal/game"
	"github.com/yourusername/werewolf-voice/internal/middleware"
	"github.com/yourusername/werewolf-voice/internal/websocket"
)

func main() {
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

	// Initialize API handler
	handler := api.NewHandler(db, gameEngine, agoraService, wsHub)

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
		public.GET("/rooms", handler.GetRooms)
	}

	// Protected routes
	protected := router.Group("/api/v1")
	protected.Use(middleware.AuthMiddleware(cfg.JWT.Secret))
	{
		// Room routes
		protected.POST("/rooms", handler.CreateRoom)
		protected.POST("/rooms/join", handler.JoinRoom)
		protected.GET("/rooms/:roomId", handler.GetRoom)
		protected.POST("/rooms/:roomId/start", handler.StartGame)
		protected.POST("/rooms/:roomId/leave", handler.LeaveRoom)
		protected.POST("/rooms/:roomId/ready", handler.SetReady)

		// Game routes
		protected.POST("/games/:sessionId/action", handler.PerformAction)
		protected.GET("/games/:sessionId", handler.GetGameState)
		protected.GET("/games/:sessionId/my-role", handler.GetMyRole)

		// Agora token
		protected.POST("/agora/token", handler.GetAgoraToken)

		// User routes
		protected.GET("/users/me", handler.GetProfile)
		protected.GET("/users/me/stats", handler.GetStats)

		// WebSocket
		protected.GET("/ws", handler.HandleWebSocket)
	}

	// Create HTTP server
	srv := &http.Server{
		Addr:         cfg.Server.Host + ":" + cfg.Server.Port,
		Handler:      router,
		ReadTimeout:  cfg.Server.ReadTimeout,
		WriteTimeout: cfg.Server.WriteTimeout,
	}

	// Start server in goroutine
	go func() {
		log.Printf("🚀 Server starting on %s", srv.Addr)
		if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	// Graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("Shutting down server...")

	ctx, cancel = context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(ctx); err != nil {
		log.Fatal("Server forced to shutdown:", err)
	}

	log.Println("Server exited")
}
