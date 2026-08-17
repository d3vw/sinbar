// client/client.go
package client

import (
	"context"
	"crypto/tls"
	"fmt"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/grey/sinbar/config"
	"github.com/grey/sinbar/daemon"
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

func (c *Client) ClearLogs(ctx context.Context) error {
	_, err := c.svc.ClearLogs(ctx, &emptypb.Empty{})
	if err != nil {
		return fmt.Errorf("clear logs: %w", err)
	}
	return nil
}
