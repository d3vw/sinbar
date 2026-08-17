package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/grey/sinbar/client"
	"github.com/grey/sinbar/config"
)

type event struct {
	Type  string `json:"type"`
	OK    bool   `json:"ok,omitempty"`
	Error string `json:"error,omitempty"`
	Data  any    `json:"data,omitempty"`
}

type metadataUpdate struct {
	Connected   bool     `json:"connected"`
	Version     string   `json:"version,omitempty"`
	APIVersion  int32    `json:"apiVersion,omitempty"`
	StartedAt   int64    `json:"startedAt,omitempty"`
	Modes       []string `json:"modes,omitempty"`
	CurrentMode string   `json:"currentMode,omitempty"`
	Error       string   `json:"error,omitempty"`
}

// The tray only needs a small subset of each connection. Keeping the stream
// compact matters because every JSON line is parsed inside the long-running
// shell process.
type connectionBatch struct {
	Events []connectionEvent
	Reset  bool
}

type connectionEvent struct {
	Type          client.ConnectionEventType
	ID            string
	Conn          compactConnection
	UplinkDelta   int64
	DownlinkDelta int64
}

type compactConnection struct {
	ID            string
	Network       string
	Destination   string
	Domain        string
	Outbound      string
	CreatedAt     int64
	ClosedAt      int64
	UplinkTotal   int64
	DownlinkTotal int64
	ProcessPath   string
}

func main() {
	flags := flag.NewFlagSet("sinbar-bridge", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	configPath := flags.String("config", config.DefaultPath(), "path to sinbar config.toml")
	host := flags.String("host", "", "sing-box API host override")
	port := flags.Int("port", 0, "sing-box API port override")
	secret := flags.String("secret", "", "sing-box API secret override")
	tlsEnabled := flags.Bool("tls", false, "enable TLS")
	if err := flags.Parse(os.Args[1:]); err != nil {
		os.Exit(2)
	}

	args := flags.Args()
	if len(args) == 0 {
		fatalJSON(errors.New("missing command (watch, watch-details, mode, select, url-test, close, close-all, clear-logs)"))
	}

	cfg, err := loadConfig(*configPath)
	if err != nil {
		fatalJSON(err)
	}
	cfg.ApplyFlags(*host, *port, *secret, *tlsEnabled)

	api := client.New(cfg)
	if err := api.Connect(); err != nil {
		fatalJSON(err)
	}
	defer api.Close()

	if args[0] == "watch" {
		watch(api)
		return
	}
	if args[0] == "watch-details" {
		watchDetails(api)
		return
	}
	if err := runAction(api, args); err != nil {
		fatalJSON(err)
	}
	_ = json.NewEncoder(os.Stdout).Encode(event{Type: "result", OK: true})
}

func loadConfig(path string) (*config.Config, error) {
	path = strings.TrimSpace(path)
	if path == "" {
		path = config.DefaultPath()
	}
	if path == "~" || strings.HasPrefix(path, "~/") {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, fmt.Errorf("resolve home directory: %w", err)
		}
		path = filepath.Join(home, strings.TrimPrefix(path, "~/"))
	}
	return config.LoadFrom(path)
}

func watch(api *client.Client) {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	encoder := json.NewEncoder(os.Stdout)
	metadata := make(chan metadataUpdate, 1)
	go pollMetadata(ctx, api, metadata)

	emit := func(kind string, data any) {
		_ = encoder.Encode(event{Type: kind, Data: data})
	}

	for {
		select {
		case <-ctx.Done():
			return
		case update := <-metadata:
			emit("metadata", update)
		case update := <-api.Service:
			emit("service", update)
		case update := <-api.Status:
			emit("status", update)
		case update := <-api.Groups:
			emit("groups", update)
		}
	}
}

func watchDetails(api *client.Client) {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	encoder := json.NewEncoder(os.Stdout)
	flushTicker := time.NewTicker(750 * time.Millisecond)
	defer flushTicker.Stop()

	var pendingConnections []client.ConnectionEvent
	connectionsReset := false
	var pendingLogs []client.LogMessage
	logsReset := false
	for {
		select {
		case <-ctx.Done():
			return
		case update := <-api.Connections:
			if update.Reset {
				pendingConnections = pendingConnections[:0]
				connectionsReset = true
			}
			pendingConnections = append(pendingConnections, update.Events...)
		case update := <-api.Logs:
			if update.Reset {
				pendingLogs = pendingLogs[:0]
				logsReset = true
			}
			for _, message := range update.Messages {
				runes := []rune(message.Message)
				if len(runes) > 500 {
					message.Message = string(runes[:499]) + "…"
				}
				pendingLogs = append(pendingLogs, message)
			}
			if len(pendingLogs) > 60 {
				pendingLogs = append([]client.LogMessage(nil), pendingLogs[len(pendingLogs)-60:]...)
			}
		case <-flushTicker.C:
			if len(pendingConnections) > 0 || connectionsReset {
				update := client.ConnectionsUpdate{Events: pendingConnections, Reset: connectionsReset}
				_ = encoder.Encode(event{Type: "connections", Data: compactConnectionUpdate(update)})
				pendingConnections = nil
				connectionsReset = false
			}
			if len(pendingLogs) > 0 || logsReset {
				update := client.LogUpdate{Messages: pendingLogs, Reset: logsReset}
				_ = encoder.Encode(event{Type: "logs", Data: update})
				pendingLogs = nil
				logsReset = false
			}
		}
	}
}

func compactConnectionUpdate(update client.ConnectionsUpdate) connectionBatch {
	batch := connectionBatch{Events: make([]connectionEvent, 0, len(update.Events)), Reset: update.Reset}
	for _, item := range update.Events {
		conn := item.Conn
		if item.Type == client.ConnectionNew && conn.ClosedAt > 0 {
			continue
		}
		batch.Events = append(batch.Events, connectionEvent{
			Type: item.Type,
			ID:   item.ID,
			Conn: compactConnection{
				ID:            conn.ID,
				Network:       conn.Network,
				Destination:   conn.Destination,
				Domain:        conn.Domain,
				Outbound:      conn.Outbound,
				CreatedAt:     conn.CreatedAt,
				ClosedAt:      conn.ClosedAt,
				UplinkTotal:   conn.UplinkTotal,
				DownlinkTotal: conn.DownlinkTotal,
				ProcessPath:   conn.ProcessPath,
			},
			UplinkDelta:   item.UplinkDelta,
			DownlinkDelta: item.DownlinkDelta,
		})
	}
	return batch
}

func pollMetadata(ctx context.Context, api *client.Client, out chan<- metadataUpdate) {
	ticker := time.NewTicker(3 * time.Second)
	defer ticker.Stop()
	last := ""

	for {
		update := fetchMetadata(ctx, api)
		raw, _ := json.Marshal(update)
		if string(raw) != last {
			select {
			case out <- update:
				last = string(raw)
			case <-ctx.Done():
				return
			}
		}

		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func fetchMetadata(parent context.Context, api *client.Client) metadataUpdate {
	ctx, cancel := context.WithTimeout(parent, 2200*time.Millisecond)
	defer cancel()

	info, err := api.GetVersion(ctx)
	if err != nil {
		return metadataUpdate{Connected: false, Error: compactError(err)}
	}
	update := metadataUpdate{Connected: true, Version: info.Version, APIVersion: info.APIVersion}
	update.StartedAt, _ = api.GetStartedAt(ctx)
	update.Modes, update.CurrentMode, _ = api.GetClashModeStatus(ctx)
	return update
}

func runAction(api *client.Client, args []string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	require := func(count int, usage string) error {
		if len(args) != count {
			return fmt.Errorf("usage: %s", usage)
		}
		return nil
	}

	switch args[0] {
	case "mode":
		if err := require(2, "mode <name>"); err != nil {
			return err
		}
		return api.SetClashMode(ctx, args[1])
	case "select":
		if err := require(3, "select <group> <outbound>"); err != nil {
			return err
		}
		return api.SelectOutbound(ctx, args[1], args[2])
	case "url-test":
		if err := require(2, "url-test <outbound>"); err != nil {
			return err
		}
		return api.URLTest(ctx, args[1])
	case "close":
		if err := require(2, "close <connection-id>"); err != nil {
			return err
		}
		return api.CloseConnection(ctx, args[1])
	case "close-all":
		if err := require(1, "close-all"); err != nil {
			return err
		}
		return api.CloseAllConnections(ctx)
	case "clear-logs":
		if err := require(1, "clear-logs"); err != nil {
			return err
		}
		return api.ClearLogs(ctx)
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func compactError(err error) string {
	if err == nil {
		return ""
	}
	text := strings.Join(strings.Fields(err.Error()), " ")
	if len(text) > 180 {
		return text[:177] + "…"
	}
	return text
}

func fatalJSON(err error) {
	_ = json.NewEncoder(os.Stdout).Encode(event{Type: "result", Error: compactError(err)})
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
