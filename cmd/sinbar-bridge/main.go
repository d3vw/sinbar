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

// savedFile is the "result" payload of taildrop-save: QML shows the basename,
// which is the only place the collision-avoiding rename becomes visible.
type savedFile struct {
	Path string `json:"path"`
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
	data, err := runAction(api, args)
	if err != nil {
		fatalJSON(err)
	}
	_ = json.NewEncoder(os.Stdout).Encode(event{Type: "result", OK: true, Data: data})
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
		case update := <-api.Tailscale:
			emit("tailscale", update)
		}
	}
}

func watchDetails(api *client.Client) {
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	encoder := json.NewEncoder(os.Stdout)
	flushTicker := time.NewTicker(750 * time.Millisecond)
	defer flushTicker.Stop()

	// The Taildrop inbox rides the detail stream rather than the always-on
	// watch, because it also carries in-flight receive progress.
	api.StartTaildropInbox()

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
		case update := <-api.Taildrop:
			_ = encoder.Encode(event{Type: "taildrop", Data: update})
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

// runAction performs a one-shot command and optionally returns a payload for
// the "result" line, which QML reads back for actions whose outcome it has to
// show — currently the path taildrop-save wrote to.
func runAction(api *client.Client, args []string) (any, error) {
	timeout := 10 * time.Second
	if len(args) > 0 && (args[0] == "taildrop-send" || args[0] == "taildrop-save" || args[0] == "taildrop-preview") {
		timeout = 24 * time.Hour
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
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
			return nil, err
		}
		return nil, api.SetClashMode(ctx, args[1])
	case "select":
		if err := require(3, "select <group> <outbound>"); err != nil {
			return nil, err
		}
		return nil, api.SelectOutbound(ctx, args[1], args[2])
	case "url-test":
		if err := require(2, "url-test <outbound>"); err != nil {
			return nil, err
		}
		return nil, api.URLTest(ctx, args[1])
	case "close":
		if err := require(2, "close <connection-id>"); err != nil {
			return nil, err
		}
		return nil, api.CloseConnection(ctx, args[1])
	case "close-all":
		if err := require(1, "close-all"); err != nil {
			return nil, err
		}
		return nil, api.CloseAllConnections(ctx)
	case "tailscale-exit":
		if err := require(3, "tailscale-exit <endpoint> <stable-id>"); err != nil {
			return nil, err
		}
		return nil, api.SetTailscaleExitNode(ctx, args[1], args[2])
	case "tailscale-exit-clear":
		if err := require(2, "tailscale-exit-clear <endpoint>"); err != nil {
			return nil, err
		}
		return nil, api.SetTailscaleExitNode(ctx, args[1], "")
	case "taildrop-send":
		if len(args) < 4 {
			return nil, fmt.Errorf("usage: taildrop-send <endpoint> <peer-id> <file>...")
		}
		return nil, api.SendTaildropFiles(ctx, args[1], args[2], args[3:])
	case "taildrop-save":
		if err := require(3, "taildrop-save <endpoint> <name>"); err != nil {
			return nil, err
		}
		dir, err := downloadDir()
		if err != nil {
			return nil, err
		}
		path, err := api.DownloadTaildropFile(ctx, args[1], args[2], dir)
		if err != nil {
			return nil, err
		}
		// A saved file leaves the inbox, matching the official Tailscale
		// clients. If the removal fails the download still succeeded, so
		// report the save — the entry just reappears in the next update.
		_ = api.DeleteTaildropFile(ctx, args[1], args[2])
		return savedFile{Path: path}, nil
	case "taildrop-preview":
		if err := require(3, "taildrop-preview <endpoint> <name>"); err != nil {
			return nil, err
		}
		dir, err := previewDir()
		if err != nil {
			return nil, err
		}
		path, err := api.PreviewTaildropFile(ctx, args[1], args[2], dir)
		if err != nil {
			return nil, err
		}
		return savedFile{Path: path}, nil
	case "taildrop-delete":
		if err := require(3, "taildrop-delete <endpoint> <name>"); err != nil {
			return nil, err
		}
		return nil, api.DeleteTaildropFile(ctx, args[1], args[2])
	case "tailscale-logout":
		if err := require(2, "tailscale-logout <endpoint>"); err != nil {
			return nil, err
		}
		return nil, api.TailscaleLogout(ctx, args[1])
	case "clear-logs":
		if err := require(1, "clear-logs"); err != nil {
			return nil, err
		}
		return nil, api.ClearLogs(ctx)
	default:
		return nil, fmt.Errorf("unknown command %q", args[0])
	}
}

// downloadDir is where taildrop-save puts received files.
func downloadDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(home, "Downloads"), nil
}

// previewDir is scratch space for taildrop-preview. It is a cache, not a
// destination: the file stays in the inbox, and each preview overwrites the
// previous copy of the same name rather than piling up numbered variants.
func previewDir() (string, error) {
	if cache := os.Getenv("XDG_CACHE_HOME"); cache != "" {
		return filepath.Join(cache, "sinbar", "taildrop"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home directory: %w", err)
	}
	return filepath.Join(home, ".cache", "sinbar", "taildrop"), nil
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
