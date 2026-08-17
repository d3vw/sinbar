package config

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/BurntSushi/toml"
)

type Config struct {
	Host       string `toml:"host"`
	Port       int    `toml:"port"`
	Secret     string `toml:"secret"`
	TLS        bool   `toml:"tls"`
	IntervalMs int64  `toml:"interval_ms"`
}

func Defaults() *Config {
	return &Config{
		Host:       "127.0.0.1",
		Port:       9999,
		IntervalMs: 1000,
	}
}

// LoadFrom reads config from path. If path does not exist, returns Defaults().
func LoadFrom(path string) (*Config, error) {
	cfg := Defaults()
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return cfg, nil
	}
	if err != nil {
		return nil, err
	}
	if err := toml.Unmarshal(data, cfg); err != nil {
		return nil, fmt.Errorf("parse %s: %w", path, err)
	}
	return cfg, nil
}

// DefaultPath returns ~/.config/sinbar/config.toml.
func DefaultPath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		home = "."
	}
	return filepath.Join(home, ".config", "sinbar", "config.toml")
}

// Load reads from DefaultPath().
func Load() (*Config, error) {
	return LoadFrom(DefaultPath())
}

// ApplyFlags overrides non-zero values from CLI flags.
func (c *Config) ApplyFlags(host string, port int, secret string, tls bool) {
	if host != "" {
		c.Host = host
	}
	if port != 0 {
		c.Port = port
	}
	if secret != "" {
		c.Secret = secret
	}
	if tls {
		c.TLS = tls
	}
}

func (c *Config) Address() string {
	return fmt.Sprintf("%s:%d", c.Host, c.Port)
}
