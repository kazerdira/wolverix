package agora

import (
	"fmt"
	"time"

	rtctokenbuilder "github.com/AgoraIO-Community/go-tokenbuilder/rtctokenbuilder"
	"github.com/kazerdira/wolverix/backend/internal/config"
)

type Service struct {
	appID          string
	appCertificate string
	tokenExpiry    uint32
}

// NewService creates a new Agora service
func NewService(cfg *config.AgoraConfig) *Service {
	return &Service{
		appID:          cfg.AppID,
		appCertificate: cfg.AppCertificate,
		tokenExpiry:    cfg.TokenExpiry,
	}
}

// GenerateRTCToken generates an RTC token for voice channel access
func (s *Service) GenerateRTCToken(channelName string, uid uint32, role rtctokenbuilder.Role) (string, error) {
	// Calculate expiration timestamp
	expireTime := uint32(time.Now().Unix()) + s.tokenExpiry

	// Build the token
	token, err := rtctokenbuilder.BuildTokenWithUID(
		s.appID,
		s.appCertificate,
		channelName,
		uid,
		role,
		expireTime,
	)
	if err != nil {
		return "", fmt.Errorf("failed to build token: %w", err)
	}

	return token, nil
}

// GeneratePublisherToken generates a token with publisher privileges
func (s *Service) GeneratePublisherToken(channelName string, uid uint32) (string, error) {
	return s.GenerateRTCToken(channelName, uid, rtctokenbuilder.RolePublisher)
}

// GenerateSubscriberToken generates a token with subscriber privileges (listen only)
func (s *Service) GenerateSubscriberToken(channelName string, uid uint32) (string, error) {
	return s.GenerateRTCToken(channelName, uid, rtctokenbuilder.RoleSubscriber)
}

// GenerateTokenWithExpiry generates a token with custom expiry
func (s *Service) GenerateTokenWithExpiry(channelName string, uid uint32, role rtctokenbuilder.Role, expirySeconds uint32) (string, error) {
	expireTime := uint32(time.Now().Unix()) + expirySeconds

	token, err := rtctokenbuilder.BuildTokenWithUID(
		s.appID,
		s.appCertificate,
		channelName,
		uid,
		role,
		expireTime,
	)
	if err != nil {
		return "", fmt.Errorf("failed to build token: %w", err)
	}

	return token, nil
}

// GetAppID returns the Agora App ID
func (s *Service) GetAppID() string {
	return s.appID
}

// GetTokenExpiry returns the token expiry in seconds
func (s *Service) GetTokenExpiry() uint32 {
	return s.tokenExpiry
}

// ValidateChannelName validates channel name format
func (s *Service) ValidateChannelName(channelName string) error {
	if len(channelName) == 0 {
		return fmt.Errorf("channel name cannot be empty")
	}
	if len(channelName) > 64 {
		return fmt.Errorf("channel name too long (max 64 characters)")
	}
	// Agora channel names must be alphanumeric with underscores and hyphens
	for _, char := range channelName {
		if !((char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') ||
			(char >= '0' && char <= '9') || char == '_' || char == '-') {
			return fmt.Errorf("channel name contains invalid characters")
		}
	}
	return nil
}
