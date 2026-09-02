import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  property bool connected: false
  property bool bridgeRunning: watchProcess.running
  property string connectionError: "Waiting for sing-box…"
  property string version: ""
  property int apiVersion: 0
  property double startedAt: 0
  property var modes: []
  property string currentMode: ""

  property int serviceStatus: 0
  property string serviceError: ""
  property double memory: 0
  property int goroutines: 0
  property int connectionsIn: 0
  property int connectionsOut: 0
  property bool trafficAvailable: false
  property double uplink: 0
  property double downlink: 0
  property double uplinkTotal: 0
  property double downlinkTotal: 0

  property var groups: []
  property var connections: []
  property string tailscaleEndpoint: ""
  property string tailscaleState: "Unavailable"
  property string tailscaleAuthUrl: ""
  property string tailscaleNetwork: ""
  property var tailscaleSelf: null
  property var tailscalePeers: []
  property var tailscaleExitNode: null
  property bool tailscaleCanShareFiles: false
  // Files other devices have sent here, still waiting in sing-box's staging
  // area. Only streamed while the panel is open.
  property var taildropInbox: []
  // Files dropped on the bar item, waiting for the user to pick a peer.
  property var pendingTaildropFiles: []
  property bool taildropPickMode: false
  property var logs: []
  property bool logsEnabled: false
  property var _connectionMap: ({})
  property var _connectionOrder: []

  property string actionStatus: ""
  property string lastError: ""
  readonly property bool busy: actionProcess.running

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configPath: expandHome(setting("configPath", "~/.config/sinbar/config.toml"))
  readonly property string pluginDir: localPath(Qt.resolvedUrl("."))
  readonly property string bridgePath: localPath(Qt.resolvedUrl("bin/sinbar-bridge"))

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function expandHome(path) {
    var value = String(path || "")
    if (value === "~") return homeDir
    if (value.indexOf("~/") === 0) return homeDir + value.substring(1)
    return value
  }

  function localPath(url) {
    var value = String(url || "")
    if (value.indexOf("file://") === 0) value = value.substring(7)
    try { return decodeURIComponent(value) } catch (e) { return value }
  }

  function shQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  // omarchy plugin add only git-clones the repo; it never builds anything.
  // Build the bridge from source on first run when it hasn't been staged
  // by `make install-local` yet.
  function bridgeCommand(args) {
    var ensureBuilt = "test -x " + shQuote(bridgePath) +
      " || (cd " + shQuote(pluginDir) + " && go build -trimpath -ldflags='-s -w' -o " +
      shQuote(bridgePath) + " ./cmd/sinbar-bridge)"
    var script = ensureBuilt + " && exec " + shQuote(bridgePath) + " \"$@\""
    return ["sh", "-c", script, "sinbar-bridge", "--config", configPath].concat(args)
  }

  function restart() {
    connected = false
    connectionError = "Reconnecting…"
    if (watchProcess.running) watchProcess.running = false
    restartTimer.restart()
  }

  function setPanelOpen(open) {
    logsEnabled = open === true
    if (logsEnabled) {
      if (!logsProcess.running) logsProcess.running = true
    } else {
      logsRestartTimer.stop()
      if (logsProcess.running) logsProcess.running = false
    }
  }

  function handleLine(line) {
    var raw = String(line || "").trim()
    if (raw === "") return
    var message
    try {
      message = JSON.parse(raw)
    } catch (e) {
      lastError = "Bridge returned invalid JSON"
      return
    }

    var data = message.data || ({})
    if (message.type === "metadata") applyMetadata(data)
    else if (message.type === "service") applyService(data)
    else if (message.type === "status") applyStatus(data)
    else if (message.type === "groups") groups = data.Groups || []
    else if (message.type === "tailscale") applyTailscale(data)
    else if (message.type === "taildrop") taildropInbox = data.files || []
    else if (message.type === "connections") applyConnections(data)
    else if (message.type === "logs") applyLogs(data)
  }

  function applyMetadata(data) {
    connected = data.connected === true
    connectionError = String(data.error || "")
    if (!connected) return
    version = String(data.version || version)
    apiVersion = Number(data.apiVersion || apiVersion)
    startedAt = Number(data.startedAt || startedAt)
    modes = data.modes || modes
    currentMode = String(data.currentMode || currentMode)
  }

  function applyService(data) {
    serviceStatus = Number(data.Status || 0)
    serviceError = String(data.ErrorMessage || "")
    if (serviceStatus === 2) connected = true
  }

  function applyStatus(data) {
    memory = Number(data.Memory || 0)
    goroutines = Number(data.Goroutines || 0)
    connectionsIn = Number(data.ConnectionsIn || 0)
    connectionsOut = Number(data.ConnectionsOut || 0)
    trafficAvailable = data.TrafficAvail === true
    uplink = Number(data.Uplink || 0)
    downlink = Number(data.Downlink || 0)
    uplinkTotal = Number(data.UplinkTotal || 0)
    downlinkTotal = Number(data.DownlinkTotal || 0)
    connected = true
  }

  function applyTailscale(data) {
    tailscaleEndpoint = String(data.endpointTag || "")
    tailscaleState = String(data.backendState || "Unavailable")
    tailscaleAuthUrl = String(data.authUrl || "")
    tailscaleNetwork = String(data.networkName || data.magicDNSSuffix || "")
    tailscaleSelf = data.self || null
    tailscalePeers = data.peers || []
    tailscaleExitNode = data.exitNode || null
    tailscaleCanShareFiles = data.canShareFiles === true
  }

  function applyConnections(data) {
    if (data.Reset === true) {
      _connectionMap = ({})
      _connectionOrder = []
    }
    var events = data.Events || []
    var map = _connectionMap
    var order = _connectionOrder.slice()
    for (var i = 0; i < events.length; i++) {
      var update = events[i] || ({})
      var id = String(update.ID || "")
      if (id === "") continue
      if (Number(update.Type) === 0) {
        var connection = update.Conn || ({})
        if (Number(connection.ClosedAt || 0) > 0) continue
        map[id] = connection
        if (order.indexOf(id) === -1) order.push(id)
      } else if (Number(update.Type) === 1) {
        var current = map[id]
        if (!current) continue
        current.UplinkTotal = Number(current.UplinkTotal || 0) + Number(update.UplinkDelta || 0)
        current.DownlinkTotal = Number(current.DownlinkTotal || 0) + Number(update.DownlinkDelta || 0)
        map[id] = current
      } else if (Number(update.Type) === 2) {
        delete map[id]
        var index = order.indexOf(id)
        if (index !== -1) order.splice(index, 1)
      }
    }
    order.sort(function(a, b) {
      return Number((map[b] || {}).CreatedAt || 0) - Number((map[a] || {}).CreatedAt || 0)
    })
    _connectionMap = map
    _connectionOrder = order
    var next = []
    for (var j = 0; j < order.length; j++) if (map[order[j]]) next.push(map[order[j]])
    connections = next
  }

  function applyLogs(data) {
    var next = data.Reset === true ? [] : logs.slice()
    var incoming = data.Messages || []
    for (var i = 0; i < incoming.length; i++) next.push(incoming[i])
    if (next.length > 240) next = next.slice(next.length - 240)
    logs = next
  }

  // doneCallback, when given, receives the path the bridge reported once the
  // action succeeds — that is how a preview knows what to hand to xdg-open.
  function runAction(args, pendingText, successText, doneCallback) {
    if (actionProcess.running) return
    actionStatus = pendingText || "Working…"
    lastError = ""
    actionProcess.successText = successText || "Done"
    actionProcess.doneCallback = doneCallback || null
    actionProcess.command = bridgeCommand(args)
    actionProcess.running = true
  }

  function setMode(mode) {
    var value = String(mode || "")
    if (value === "") return
    currentMode = value
    runAction(["mode", value], "Switching mode…", "Mode: " + value)
  }

  function selectOutbound(group, outbound) {
    runAction(["select", String(group), String(outbound)], "Switching route…", "Route switched")
  }

  function urlTest(outbound) {
    runAction(["url-test", String(outbound)], "Testing latency…", "Latency test started")
  }

  function closeConnection(id) {
    runAction(["close", String(id)], "Closing connection…", "Connection closed")
  }

  function closeAllConnections() {
    runAction(["close-all"], "Closing all connections…", "All connections closed")
  }

  function chooseTaildropFiles(peer) {
    if (!peer || !peer.id || peer.canReceiveFiles !== true || !tailscaleCanShareFiles || filePicker.running) return
    filePicker.peerID = String(peer.id)
    filePicker.peerName = String(peer.hostName || peer.dnsName || "peer")
    filePicker.command = ["omarchy-file-select", "--title", "Send with Tailscale", "--multiple"]
    filePicker.running = true
  }

  function taildropEligible(peer) {
    return peer && peer.id && peer.online === true && peer.canReceiveFiles === true
      && tailscaleCanShareFiles && tailscaleEndpoint !== ""
  }

  // Convert a drag-and-drop url list into local file paths and enter the
  // "pick a peer" state. Directories and non-local urls are dropped here so
  // the recipient list only has to worry about a clean file list.
  function beginTaildropDrop(urls) {
    var files = []
    for (var i = 0; i < (urls || []).length; i++) {
      var raw = String(urls[i] || "")
      if (raw.indexOf("file://") !== 0) continue
      if (raw.charAt(raw.length - 1) === "/") continue
      var path = localPath(raw)
      if (path !== "") files.push(path)
    }
    pendingTaildropFiles = files
    taildropPickMode = files.length > 0
    return taildropPickMode
  }

  function sendTaildropTo(peer) {
    if (!taildropPickMode || pendingTaildropFiles.length === 0) return
    if (!taildropEligible(peer) || actionProcess.running) return
    var files = pendingTaildropFiles.slice()
    var name = String(peer.hostName || peer.dnsName || "peer")
    runAction(["taildrop-send", tailscaleEndpoint, String(peer.id)].concat(files),
              "Sending " + files.length + " file(s)…", "Sent to " + name)
    pendingTaildropFiles = []
    taildropPickMode = false
  }

  function cancelTaildropDrop() {
    pendingTaildropFiles = []
    taildropPickMode = false
  }

  function saveTaildropFile(file) {
    if (!file || !file.name || tailscaleEndpoint === "") return
    // %s is filled from the path the bridge reports, so a name that collided
    // in ~/Downloads shows the rename it actually got.
    runAction(["taildrop-save", tailscaleEndpoint, String(file.name)],
              "Saving " + String(file.name) + "…", "Saved · %s")
  }

  // Emitted once a previewed file is staged on disk. The panel owns the launch
  // because it also owns the keyboard grab it has to hand back first.
  signal previewReady(string path)

  // Stage a received file so it can be opened with whatever the desktop uses
  // for its type. It goes to a cache directory rather than being saved: a look
  // must not consume it, so it stays in the inbox and the save button keeps
  // its meaning.
  function previewTaildropFile(file) {
    if (!file || !file.name || tailscaleEndpoint === "") return
    runAction(["taildrop-preview", tailscaleEndpoint, String(file.name)],
              "Opening " + String(file.name) + "…", "Opened " + String(file.name),
              function(path) { if (path !== "") root.previewReady(path) })
  }

  function deleteTaildropFile(file) {
    if (!file || !file.name || tailscaleEndpoint === "") return
    runAction(["taildrop-delete", tailscaleEndpoint, String(file.name)],
              "Discarding " + String(file.name) + "…", "Discarded " + String(file.name))
  }

  function setTailscaleExitNode(peer) {
    if (!peer || !peer.id || tailscaleEndpoint === "") return
    runAction(["tailscale-exit", tailscaleEndpoint, String(peer.id)], "Switching exit node…", "Exit node switched")
  }

  function clearTailscaleExitNode() {
    if (tailscaleEndpoint !== "") runAction(["tailscale-exit-clear", tailscaleEndpoint], "Clearing exit node…", "Exit node cleared")
  }

  function tailscaleLogout() {
    if (tailscaleEndpoint !== "") runAction(["tailscale-logout", tailscaleEndpoint], "Logging out…", "Tailscale logged out")
  }

  function clearLogs() {
    logs = []
    runAction(["clear-logs"], "Clearing logs…", "Logs cleared")
  }

  Process {
    id: watchProcess
    command: root.bridgeCommand(["watch"])
    running: true
    stdout: SplitParser { onRead: function(data) { root.handleLine(data) } }
    stderr: SplitParser {
      onRead: function(data) {
        var text = String(data || "").trim()
        if (text !== "") root.connectionError = text
      }
    }
    onRunningChanged: if (!running && !restartTimer.running) restartTimer.restart()
  }

  Process {
    id: logsProcess
    command: root.bridgeCommand(["watch-details"])
    running: false
    stdout: SplitParser { onRead: function(data) { root.handleLine(data) } }
    stderr: SplitParser {
      onRead: function(data) {
        var text = String(data || "").trim()
        if (text !== "") root.lastError = text
      }
    }
    onRunningChanged: if (!running && root.logsEnabled && !logsRestartTimer.running) logsRestartTimer.restart()
  }

  Process {
    id: filePicker
    property string peerID: ""
    property string peerName: ""
    command: []
    running: false
    stdout: StdioCollector { id: pickerStdout; waitForEnd: true }
    stderr: StdioCollector { id: pickerStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 1) return
      if (exitCode !== 0) {
        root.lastError = String(pickerStderr.text || "File picker failed").trim()
        return
      }
      var lines = String(pickerStdout.text || "").split("\n")
      var files = []
      for (var i = 0; i < lines.length; i++) {
        var path = lines[i].trim()
        if (path !== "") files.push(path)
      }
      if (files.length === 0) return
      root.runAction(["taildrop-send", root.tailscaleEndpoint, peerID].concat(files),
                     "Sending " + files.length + " file(s)…", "Sent to " + peerName)
    }
  }

  Process {
    id: actionProcess
    property string successText: ""
    property var doneCallback: null
    property string output: ""
    command: []
    running: false
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onRunningChanged: if (running) output = ""
    onExited: function(exitCode) {
      var raw = String(actionStdout.text || "").trim()
      var errorText = String(actionStderr.text || "").trim()
      var resultPath = ""
      if (raw !== "") {
        try {
          var result = JSON.parse(raw.split("\n").pop())
          if (result.error) errorText = String(result.error)
          if (result.data && result.data.path) resultPath = String(result.data.path)
        } catch (e) {}
      }
      var callback = doneCallback
      doneCallback = null
      if (exitCode === 0 && errorText === "") {
        root.actionStatus = resultPath !== "" && successText.indexOf("%s") !== -1
          ? successText.replace("%s", resultPath.split("/").pop())
          : successText.replace("%s", "")
        root.lastError = ""
        if (callback) callback(resultPath)
      } else {
        root.actionStatus = ""
        root.lastError = errorText || "Bridge action failed"
      }
      actionStatusTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 1800
    repeat: false
    onTriggered: if (!watchProcess.running) watchProcess.running = true
  }

  Timer {
    id: logsRestartTimer
    interval: 1800
    repeat: false
    onTriggered: if (root.logsEnabled && !logsProcess.running) logsProcess.running = true
  }

  Timer {
    id: actionStatusTimer
    interval: 2600
    repeat: false
    onTriggered: root.actionStatus = ""
  }
}
