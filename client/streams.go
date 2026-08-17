// client/streams.go
package client

import (
	"time"

	"google.golang.org/protobuf/types/known/emptypb"

	"github.com/grey/sinbar/daemon"
)

func (c *Client) startStreams() {
	go c.runServiceStream()
	go c.runStatusStream()
	go c.runGroupsStream()
	go c.runConnectionsStream()
	go c.runLogStream()
}

// withRetry runs fn in a loop, applying exponential backoff on error.
// Exits cleanly when c.ctx is cancelled.
func (c *Client) withRetry(fn func() error) {
	backoff := time.Second
	for {
		select {
		case <-c.ctx.Done():
			return
		default:
		}
		if err := fn(); err != nil {
			select {
			case <-c.ctx.Done():
				return
			case <-time.After(backoff):
				if backoff < 30*time.Second {
					backoff *= 2
				}
			}
		} else {
			backoff = time.Second
		}
	}
}

func (c *Client) runServiceStream() {
	c.withRetry(func() error {
		stream, err := c.svc.SubscribeServiceStatus(c.ctx, &emptypb.Empty{})
		if err != nil {
			return err
		}
		for {
			msg, err := stream.Recv()
			if err != nil {
				return err
			}
			sendLatest(c.Service, translateServiceStatus(msg))
		}
	})
}

func (c *Client) runStatusStream() {
	c.withRetry(func() error {
		stream, err := c.svc.SubscribeStatus(c.ctx, &daemon.SubscribeStatusRequest{
			// The StartedService protobuf carries a Go time.Duration in
			// nanoseconds, while lazy-box config exposes milliseconds.
			Interval: int64(time.Duration(c.cfg.IntervalMs) * time.Millisecond),
		})
		if err != nil {
			return err
		}
		for {
			msg, err := stream.Recv()
			if err != nil {
				return err
			}
			update := translateStatus(msg)
			// sing-box reports bytes transferred during the requested interval,
			// not a pre-normalized bytes/second value.
			if c.cfg.IntervalMs > 0 && c.cfg.IntervalMs != 1000 {
				update.Uplink = int64(float64(update.Uplink) * 1000 / float64(c.cfg.IntervalMs))
				update.Downlink = int64(float64(update.Downlink) * 1000 / float64(c.cfg.IntervalMs))
			}
			sendLatest(c.Status, update)
		}
	})
}

func (c *Client) runGroupsStream() {
	c.withRetry(func() error {
		stream, err := c.svc.SubscribeGroups(c.ctx, &emptypb.Empty{})
		if err != nil {
			return err
		}
		for {
			msg, err := stream.Recv()
			if err != nil {
				return err
			}
			sendLatest(c.Groups, translateGroups(msg))
		}
	})
}

func (c *Client) runConnectionsStream() {
	c.withRetry(func() error {
		stream, err := c.svc.SubscribeConnections(c.ctx, &daemon.SubscribeConnectionsRequest{
			Interval: int64(time.Duration(c.cfg.IntervalMs) * time.Millisecond),
		})
		if err != nil {
			return err
		}
		for {
			msg, err := stream.Recv()
			if err != nil {
				return err
			}
			c.Connections <- translateConnections(msg)
		}
	})
}

func (c *Client) runLogStream() {
	c.withRetry(func() error {
		stream, err := c.svc.SubscribeLog(c.ctx, &emptypb.Empty{})
		if err != nil {
			return err
		}
		for {
			msg, err := stream.Recv()
			if err != nil {
				return err
			}
			c.Logs <- translateLog(msg)
		}
	})
}

// sendLatest does a non-blocking send that drops the stale value when the
// single-slot channel is full — so the consumer always sees the latest update.
func sendLatest[T any](ch chan T, v T) {
	select {
	case ch <- v:
	default:
		select {
		case <-ch:
		default:
		}
		ch <- v
	}
}

// ── Translators ────────────────────────────────────────────────────────────

func translateServiceStatus(s *daemon.ServiceStatus) ServiceStatusUpdate {
	return ServiceStatusUpdate{
		Status:       ServiceStatus(s.Status),
		ErrorMessage: s.ErrorMessage,
	}
}

func translateStatus(s *daemon.Status) StatusUpdate {
	return StatusUpdate{
		Memory:         s.Memory,
		Goroutines:     s.Goroutines,
		ConnectionsIn:  s.ConnectionsIn,
		ConnectionsOut: s.ConnectionsOut,
		TrafficAvail:   s.TrafficAvailable,
		Uplink:         s.Uplink,
		Downlink:       s.Downlink,
		UplinkTotal:    s.UplinkTotal,
		DownlinkTotal:  s.DownlinkTotal,
	}
}

func translateGroups(g *daemon.Groups) GroupsUpdate {
	out := GroupsUpdate{Groups: make([]Group, len(g.Group))}
	for i, grp := range g.Group {
		items := make([]GroupItem, len(grp.Items))
		for j, it := range grp.Items {
			items[j] = GroupItem{
				Tag:       it.Tag,
				Type:      it.Type,
				TestTime:  it.UrlTestTime,
				TestDelay: it.UrlTestDelay,
			}
		}
		out.Groups[i] = Group{
			Tag:        grp.Tag,
			Type:       grp.Type,
			Selectable: grp.Selectable,
			Selected:   grp.Selected,
			IsExpand:   grp.IsExpand,
			Items:      items,
		}
	}
	return out
}

func translateConnections(e *daemon.ConnectionEvents) ConnectionsUpdate {
	out := ConnectionsUpdate{
		Events: make([]ConnectionEvent, len(e.Events)),
		Reset:  e.Reset_,
	}
	for i, ev := range e.Events {
		var conn Connection
		if ev.Connection != nil {
			c := ev.Connection
			var pid uint32
			var ppath string
			if c.ProcessInfo != nil {
				pid = c.ProcessInfo.ProcessId
				ppath = c.ProcessInfo.ProcessPath
			}
			conn = Connection{
				ID: c.Id, Inbound: c.Inbound, InboundType: c.InboundType,
				IPVersion: c.IpVersion,
				Network:   c.Network, Source: c.Source, Destination: c.Destination,
				Domain: c.Domain, Protocol: c.Protocol, User: c.User,
				Outbound: c.Outbound, OutboundType: c.OutboundType,
				ChainList: c.ChainList, CreatedAt: c.CreatedAt, ClosedAt: c.ClosedAt,
				Uplink: c.Uplink, Downlink: c.Downlink,
				UplinkTotal: c.UplinkTotal, DownlinkTotal: c.DownlinkTotal,
				Rule: c.Rule, ProcessPath: ppath, ProcessID: pid,
			}
		}
		out.Events[i] = ConnectionEvent{
			Type: ConnectionEventType(ev.Type), ID: ev.Id, Conn: conn,
			UplinkDelta: ev.UplinkDelta, DownlinkDelta: ev.DownlinkDelta,
			ClosedAt: ev.ClosedAt,
		}
	}
	return out
}

func translateLog(l *daemon.Log) LogUpdate {
	out := LogUpdate{
		Messages: make([]LogMessage, len(l.Messages)),
		Reset:    l.Reset_,
	}
	for i, m := range l.Messages {
		plain, rich := colorizeANSI(m.Message)
		out.Messages[i] = LogMessage{
			Level:       LogLevel(m.Level),
			Message:     plain,
			MessageRich: rich,
		}
	}
	return out
}
