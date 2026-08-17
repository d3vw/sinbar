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
  property var logs: []
  property bool logsEnabled: false
  property var _connectionMap: ({})
  property var _connectionOrder: []

  property string actionStatus: ""
  property string lastError: ""
  readonly property bool busy: actionProcess.running

  readonly property string homeDir: Quickshell.env("HOME") || ""
  readonly property string configPath: expandHome(setting("configPath", "~/.config/sinbar/config.toml"))
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

  function bridgeCommand(args) {
    return [bridgePath, "--config", configPath].concat(args)
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

  function runAction(args, pendingText, successText) {
    if (actionProcess.running) return
    actionStatus = pendingText || "Working…"
    lastError = ""
    actionProcess.successText = successText || "Done"
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
    id: actionProcess
    property string successText: ""
    property string output: ""
    command: []
    running: false
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onRunningChanged: if (running) output = ""
    onExited: function(exitCode) {
      var raw = String(actionStdout.text || "").trim()
      var errorText = String(actionStderr.text || "").trim()
      if (raw !== "") {
        try {
          var result = JSON.parse(raw.split("\n").pop())
          if (result.error) errorText = String(result.error)
        } catch (e) {}
      }
      if (exitCode === 0 && errorText === "") {
        root.actionStatus = successText
        root.lastError = ""
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
