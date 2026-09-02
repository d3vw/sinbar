// client/client.go
package client

import (
	"context"
	"crypto/tls"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/d3vw/sinbar/config"
	"github.com/d3vw/sinbar/daemon"
)

// Client wraps a gRPC connection to sing-box's StartedService.
// After Connect(), the Status/Groups/Connections/Logs/Service channels
// emit updates from persistent background streams.
type Client struct {
	cfg  *config.Config
	conn *grpc.ClientConn
	svc  daemon.StartedServiceClient

	Status      chan StatusUpdate
	Groups      chan GroupsUpdate
	Connections chan ConnectionsUpdate
	Logs        chan LogUpdate
	Service     chan ServiceStatusUpdate
	Tailscale   chan TailscaleStatusUpdate
	Taildrop    chan TaildropInboxUpdate

	ctx    context.Context
	cancel context.CancelFunc
}

func New(cfg *config.Config) *Client {
	ctx, cancel := context.WithCancel(context.Background())
	return &Client{
		cfg:         cfg,
		Status:      make(chan StatusUpdate, 1),
		Groups:      make(chan GroupsUpdate, 1),
		Connections: make(chan ConnectionsUpdate, 100),
		Logs:        make(chan LogUpdate, 100),
		Service:     make(chan ServiceStatusUpdate, 4),
		Tailscale:   make(chan TailscaleStatusUpdate, 1),
		Taildrop:    make(chan TaildropInboxUpdate, 1),
		ctx:         ctx,
		cancel:      cancel,
	}
}

func (c *Client) Connect() error {
	var creds credentials.TransportCredentials
	if c.cfg.TLS {
		creds = credentials.NewTLS(&tls.Config{})
	} else {
		creds = insecure.NewCredentials()
	}

	conn, err := grpc.NewClient(
		c.cfg.Address(),
		grpc.WithTransportCredentials(creds),
		grpc.WithUnaryInterceptor(c.authUnary()),
		grpc.WithStreamInterceptor(c.authStream()),
	)
	if err != nil {
		return fmt.Errorf("grpc dial %s: %w", c.cfg.Address(), err)
	}
	c.conn = conn
	c.svc = daemon.NewStartedServiceClient(conn)
	c.startStreams()
	return nil
}

func (c *Client) Close() {
	c.cancel()
	if c.conn != nil {
		c.conn.Close()
	}
}

func (c *Client) authUnary() grpc.UnaryClientInterceptor {
	return func(ctx context.Context, method string, req, reply any, cc *grpc.ClientConn, invoker grpc.UnaryInvoker, opts ...grpc.CallOption) error {
		return invoker(c.withAuth(ctx), method, req, reply, cc, opts...)
	}
}

func (c *Client) authStream() grpc.StreamClientInterceptor {
	return func(ctx context.Context, desc *grpc.StreamDesc, cc *grpc.ClientConn, method string, streamer grpc.Streamer, opts ...grpc.CallOption) (grpc.ClientStream, error) {
		return streamer(c.withAuth(ctx), desc, cc, method, opts...)
	}
}

func (c *Client) withAuth(ctx context.Context) context.Context {
	if c.cfg.Secret == "" {
		return ctx
	}
	return metadata.AppendToOutgoingContext(ctx, "authorization", "Bearer "+c.cfg.Secret)
}

// ── One-shot RPCs ──────────────────────────────────────────────────────────

func (c *Client) GetVersion(ctx context.Context) (VersionInfo, error) {
	resp, err := c.svc.GetVersion(ctx, &emptypb.Empty{})
	if err != nil {
		return VersionInfo{}, fmt.Errorf("get version: %w", err)
	}
	return VersionInfo{Version: resp.Version, APIVersion: resp.ApiVersion}, nil
}

func (c *Client) GetStartedAt(ctx context.Context) (int64, error) {
	resp, err := c.svc.GetStartedAt(ctx, &emptypb.Empty{})
	if err != nil {
		return 0, fmt.Errorf("get started at: %w", err)
	}
	return resp.StartedAt, nil
}

func (c *Client) GetClashModeStatus(ctx context.Context) ([]string, string, error) {
	resp, err := c.svc.GetClashModeStatus(ctx, &emptypb.Empty{})
	if err != nil {
		return nil, "", fmt.Errorf("get clash mode status: %w", err)
	}
	return resp.ModeList, resp.CurrentMode, nil
}

func (c *Client) SelectOutbound(ctx context.Context, groupTag, outboundTag string) error {
	_, err := c.svc.SelectOutbound(ctx, &daemon.SelectOutboundRequest{
		GroupTag:    groupTag,
		OutboundTag: outboundTag,
	})
	if err != nil {
		return fmt.Errorf("select outbound: %w", err)
	}
	return nil
}

func (c *Client) URLTest(ctx context.Context, outboundTag string) error {
	_, err := c.svc.URLTest(ctx, &daemon.URLTestRequest{OutboundTag: outboundTag})
	if err != nil {
		return fmt.Errorf("url test: %w", err)
	}
	return nil
}

func (c *Client) SetClashMode(ctx context.Context, mode string) error {
	_, err := c.svc.SetClashMode(ctx, &daemon.ClashMode{Mode: mode})
	if err != nil {
		return fmt.Errorf("set clash mode: %w", err)
	}
	return nil
}

func (c *Client) CloseConnection(ctx context.Context, id string) error {
	_, err := c.svc.CloseConnection(ctx, &daemon.CloseConnectionRequest{Id: id})
	if err != nil {
		return fmt.Errorf("close connection: %w", err)
	}
	return nil
}

func (c *Client) CloseAllConnections(ctx context.Context) error {
	_, err := c.svc.CloseAllConnections(ctx, &emptypb.Empty{})
	if err != nil {
		return fmt.Errorf("close all connections: %w", err)
	}
	return nil
}

func (c *Client) SetGroupExpand(ctx context.Context, groupTag string, isExpand bool) error {
	_, err := c.svc.SetGroupExpand(ctx, &daemon.SetGroupExpandRequest{
		GroupTag: groupTag,
		IsExpand: isExpand,
	})
	if err != nil {
		return fmt.Errorf("set group expand: %w", err)
	}
	return nil
}

func (c *Client) SetTailscaleExitNode(ctx context.Context, endpointTag, stableID string) error {
	_, err := c.svc.SetTailscaleExitNode(ctx, &daemon.SetTailscaleExitNodeRequest{EndpointTag: endpointTag, StableID: stableID})
	if err != nil {
		return fmt.Errorf("set tailscale exit node: %w", err)
	}
	return nil
}

func (c *Client) SendTaildropFiles(ctx context.Context, endpointTag, peerID string, paths []string) error {
	manifest := make([]*daemon.TaildropOutgoingFile, 0, len(paths))
	for _, path := range paths {
		info, err := os.Stat(path)
		if err != nil {
			return fmt.Errorf("open taildrop file: %w", err)
		}
		if info.IsDir() {
			return fmt.Errorf("directories are not supported: %s", path)
		}
		manifest = append(manifest, &daemon.TaildropOutgoingFile{Name: filepath.Base(path), Size: info.Size()})
	}
	stream, err := c.svc.SendTaildropFiles(ctx)
	if err != nil {
		return fmt.Errorf("start taildrop: %w", err)
	}
	if err = stream.Send(&daemon.TaildropSendClientMessage{Message: &daemon.TaildropSendClientMessage_Start{Start: &daemon.TaildropSendStart{EndpointTag: endpointTag, PeerStableID: peerID, Files: manifest}}}); err != nil {
		return fmt.Errorf("start taildrop upload: %w", err)
	}
	// Keep messages below gRPC's transport frame boundary, matching sing-box.
	buffer := make([]byte, 16*1024-64)
	for _, path := range paths {
		file, openErr := os.Open(path)
		if openErr != nil {
			return openErr
		}
		for {
			n, readErr := file.Read(buffer)
			if n > 0 {
				if err = stream.Send(&daemon.TaildropSendClientMessage{Message: &daemon.TaildropSendClientMessage_Chunk{Chunk: &daemon.TaildropFileChunk{Data: buffer[:n]}}}); err != nil {
					file.Close()
					return fmt.Errorf("send taildrop data: %w", err)
				}
			}
			if readErr == io.EOF {
				break
			}
			if readErr != nil {
				file.Close()
				return readErr
			}
		}
		file.Close()
		if err = stream.Send(&daemon.TaildropSendClientMessage{Message: &daemon.TaildropSendClientMessage_FileDone{FileDone: &daemon.TaildropFileDone{}}}); err != nil {
			return err
		}
	}
	if err = stream.CloseSend(); err != nil {
		return err
	}
	for {
		_, err = stream.Recv()
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return fmt.Errorf("finish taildrop: %w", err)
		}
	}
}

// DownloadTaildropFile writes one waiting inbox file into dir under a name that
// does not collide with anything already there, and reports the path it landed
// on. The file stays in the inbox; removing it is a separate
// DeleteTaildropFile call.
func (c *Client) DownloadTaildropFile(ctx context.Context, endpointTag, name, dir string) (string, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("create download directory: %w", err)
	}
	path := uniquePath(dir, name)
	if err := c.downloadTaildropFileTo(ctx, endpointTag, name, path); err != nil {
		return "", err
	}
	return path, nil
}

// PreviewTaildropFile writes one waiting inbox file into dir under its own
// name, replacing whatever an earlier preview of the same name left there, and
// reports the path. Unlike a save this keeps no history and does not touch the
// inbox: looking at a file must not consume it.
func (c *Client) PreviewTaildropFile(ctx context.Context, endpointTag, name, dir string) (string, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", fmt.Errorf("create preview directory: %w", err)
	}
	path := filepath.Join(dir, safeBase(name))
	if err := c.downloadTaildropFileTo(ctx, endpointTag, name, path); err != nil {
		return "", err
	}
	return path, nil
}

func (c *Client) downloadTaildropFileTo(ctx context.Context, endpointTag, name, path string) error {
	stream, err := c.svc.DownloadTaildropFile(ctx, &daemon.DownloadTaildropFileRequest{EndpointTag: endpointTag, Name: name})
	if err != nil {
		return fmt.Errorf("download taildrop file: %w", err)
	}
	// Collect into a .part sibling and rename only once the stream ends
	// cleanly, so an interrupted transfer never leaves a truncated file
	// looking complete — nor replaces a good earlier copy with one.
	partPath := path + ".part"
	file, err := os.OpenFile(partPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	abandon := func(cause error) error {
		file.Close()
		os.Remove(partPath)
		return cause
	}
	for {
		chunk, recvErr := stream.Recv()
		if recvErr == io.EOF {
			break
		}
		if recvErr != nil {
			return abandon(fmt.Errorf("download taildrop file: %w", recvErr))
		}
		if len(chunk.Data) == 0 {
			continue
		}
		if _, err = file.Write(chunk.Data); err != nil {
			return abandon(err)
		}
	}
	if err = file.Close(); err != nil {
		os.Remove(partPath)
		return err
	}
	if err = os.Rename(partPath, path); err != nil {
		os.Remove(partPath)
		return err
	}
	return nil
}

func (c *Client) DeleteTaildropFile(ctx context.Context, endpointTag, name string) error {
	_, err := c.svc.DeleteTaildropFile(ctx, &daemon.DeleteTaildropFileRequest{EndpointTag: endpointTag, Name: name})
	if err != nil {
		return fmt.Errorf("delete taildrop file: %w", err)
	}
	return nil
}

// safeBase reduces a peer-supplied file name to a single path element. The name
// arrives over the network, so a sender must not be able to steer a write
// outside the destination directory with something like "../../.bashrc".
func safeBase(name string) string {
	base := filepath.Base(filepath.FromSlash(name))
	if base == "." || base == ".." || base == string(filepath.Separator) || base == "" {
		return "taildrop-file"
	}
	return base
}

// uniquePath resolves name against dir without clobbering an existing file,
// inserting " (n)" before the extension the way file managers do.
func uniquePath(dir, name string) string {
	base := safeBase(name)
	candidate := filepath.Join(dir, base)
	if _, err := os.Stat(candidate); os.IsNotExist(err) {
		return candidate
	}
	ext := filepath.Ext(base)
	stem := strings.TrimSuffix(base, ext)
	// filepath.Ext(".bashrc") is the whole name, which would leave an empty
	// stem and rename to " (1).bashrc". A dotfile has no extension to split.
	if stem == "" {
		stem, ext = base, ""
	}
	for n := 1; n < 1000; n++ {
		candidate = filepath.Join(dir, fmt.Sprintf("%s (%d)%s", stem, n, ext))
		if _, err := os.Stat(candidate); os.IsNotExist(err) {
			return candidate
		}
	}
	return filepath.Join(dir, fmt.Sprintf("%s-%d%s", stem, time.Now().UnixNano(), ext))
}

func (c *Client) TailscaleLogout(ctx context.Context, endpointTag string) error {
	_, err := c.svc.TailscaleLogout(ctx, &daemon.TailscaleLogoutRequest{EndpointTag: endpointTag})
	if err != nil {
		return fmt.Errorf("tailscale logout: %w", err)
	}
	return nil
}

func (c *Client) ClearLogs(ctx context.Context) error {
	_, err := c.svc.ClearLogs(ctx, &emptypb.Empty{})
	if err != nil {
		return fmt.Errorf("clear logs: %w", err)
	}
	return nil
}
