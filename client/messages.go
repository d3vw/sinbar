// client/messages.go
package client

// ServiceStatus mirrors daemon.ServiceStatus_Type.
type ServiceStatus int32

const (
	ServiceIdle     ServiceStatus = 0
	ServiceStarting ServiceStatus = 1
	ServiceStarted  ServiceStatus = 2
	ServiceStopping ServiceStatus = 3
	ServiceFatal    ServiceStatus = 4
)

func (s ServiceStatus) String() string {
	switch s {
	case ServiceIdle:
		return "IDLE"
	case ServiceStarting:
		return "STARTING"
	case ServiceStarted:
		return "STARTED"
	case ServiceStopping:
		return "STOPPING"
	case ServiceFatal:
		return "FATAL"
	default:
		return "UNKNOWN"
	}
}

type ServiceStatusUpdate struct {
	Status       ServiceStatus
	ErrorMessage string
}

type LogLevel int32

const (
	LogPanic LogLevel = 0
	LogFatal LogLevel = 1
	LogError LogLevel = 2
	LogWarn  LogLevel = 3
	LogInfo  LogLevel = 4
	LogDebug LogLevel = 5
	LogTrace LogLevel = 6
)

type LogMessage struct {
	Level       LogLevel
	Message     string // ANSI-stripped plain text
	MessageRich string // same text with ANSI color runs as QML rich-text <font> spans
}

type LogUpdate struct {
	Messages []LogMessage
	Reset    bool
}

type StatusUpdate struct {
	Memory         uint64
	Goroutines     int32
	ConnectionsIn  int32
	ConnectionsOut int32
	TrafficAvail   bool
	Uplink         int64
	Downlink       int64
	UplinkTotal    int64
	DownlinkTotal  int64
}

type GroupItem struct {
	Tag       string
	Type      string
	TestTime  int64
	TestDelay int32 // ms; 0 = untested
}

type Group struct {
	Tag        string
	Type       string
	Selectable bool
	Selected   string
	IsExpand   bool
	Items      []GroupItem
}

type GroupsUpdate struct {
	Groups []Group
}

type ConnectionEventType int32

const (
	ConnectionNew    ConnectionEventType = 0
	ConnectionUpdate ConnectionEventType = 1
	ConnectionClosed ConnectionEventType = 2
)

type Connection struct {
	ID            string
	Inbound       string
	InboundType   string
	IPVersion     int32
	Network       string
	Source        string
	Destination   string
	Domain        string
	Protocol      string
	User          string
	Outbound      string
	OutboundType  string
	ChainList     []string
	CreatedAt     int64
	ClosedAt      int64
	Uplink        int64
	Downlink      int64
	UplinkTotal   int64
	DownlinkTotal int64
	Rule          string
	ProcessPath   string
	ProcessID     uint32
}

type ConnectionEvent struct {
	Type          ConnectionEventType
	ID            string
	Conn          Connection
	UplinkDelta   int64
	DownlinkDelta int64
	ClosedAt      int64
}

type ConnectionsUpdate struct {
	Events []ConnectionEvent
	Reset  bool
}

type VersionInfo struct {
	Version    string
	APIVersion int32
}

type ClashModeUpdate struct {
	Mode string
}

type TailscalePeer struct {
	HostName        string   `json:"hostName"`
	DNSName         string   `json:"dnsName"`
	OS              string   `json:"os"`
	TailscaleIPs    []string `json:"tailscaleIPs"`
	Online          bool     `json:"online"`
	ExitNode        bool     `json:"exitNode"`
	ExitNodeOption  bool     `json:"exitNodeOption"`
	Active          bool     `json:"active"`
	StableID        string   `json:"id"`
	UserID          int64    `json:"userID,omitempty"`
	LoginName       string   `json:"loginName,omitempty"`
	CanReceiveFiles bool     `json:"canReceiveFiles"`
}

// TaildropFile is one file another device has sent to this node and that is
// still waiting in sing-box's Taildrop staging area.
type TaildropFile struct {
	Name       string `json:"name"`
	Size       int64  `json:"size"`
	SenderName string `json:"senderName"`
	ModifiedAt int64  `json:"modifiedAt"`
}

type TaildropInboxUpdate struct {
	EndpointTag string         `json:"endpointTag"`
	Files       []TaildropFile `json:"files"`
}

type TailscaleStatusUpdate struct {
	EndpointTag   string          `json:"endpointTag"`
	BackendState  string          `json:"backendState"`
	AuthURL       string          `json:"authUrl,omitempty"`
	NetworkName   string          `json:"networkName,omitempty"`
	MagicDNS      string          `json:"magicDNSSuffix,omitempty"`
	KeyAuth       bool            `json:"keyAuth"`
	CanShareFiles bool            `json:"canShareFiles"`
	Self          *TailscalePeer  `json:"self,omitempty"`
	Peers         []TailscalePeer `json:"peers"`
	ExitNode      *TailscalePeer  `json:"exitNode,omitempty"`
}
