import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.grey.sinbar"
  ipcTarget: "io.github.grey.sinbar"
  manageIpc: false

  property int activeTab: 0
  property int groupIndex: 0
  property int routeIndex: 0
  property int connectionIndex: 0
  property bool cursorActive: false
  property string logFilterText: ""
  property bool logFilterEditing: false
  property bool inboxCollapsed: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barText: bar ? bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color faint: Qt.darker(foreground, 2.05)
  // barText already tracks the bar's real (possibly sampled) background,
  // unlike the static theme foreground above — the speed readout lives in
  // the bar chrome itself, so its dim/faint shades must derive from that.
  readonly property color barDim: Qt.darker(barText, 1.55)
  readonly property color barFaint: Qt.darker(barText, 2.05)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool showSpeeds: String(setting("showSpeeds", "On")) === "On"
  readonly property string tuiCommand: String(setting("tuiCommand", ""))
  readonly property var selectableGroups: proxy && proxy.groups ? filteredGroups() : []
  readonly property var filteredLogs: proxy && proxy.logs ? computeFilteredLogs() : []
  readonly property var currentGroup: arrayLength(selectableGroups) > 0
    ? selectableGroups[Math.max(0, Math.min(groupIndex, arrayLength(selectableGroups) - 1))]
    : null
  readonly property var currentRoutes: currentGroup ? (currentGroup.Items || []) : []
  readonly property var selectedRoute: arrayLength(currentRoutes) > 0
    ? currentRoutes[Math.max(0, Math.min(routeIndex, arrayLength(currentRoutes) - 1))]
    : null
  readonly property var selectedConnection: proxy && arrayLength(proxy.connections) > 0
    ? proxy.connections[Math.max(0, Math.min(connectionIndex, arrayLength(proxy.connections) - 1))]
    : null
  readonly property string statusLabel: {
    if (!proxy.connected) return "OFFLINE"
    if (proxy.serviceStatus === 2) return "RUNNING"
    if (proxy.serviceStatus === 1) return "STARTING"
    if (proxy.serviceStatus === 3) return "STOPPING"
    if (proxy.serviceStatus === 4) return "FATAL"
    return "CONNECTED"
  }
  readonly property string statusGlyph: "󰏗"
  readonly property color statusColor: proxy.connected ? foreground : urgent

  function arrayLength(value) {
    if (value === undefined || value === null || value.length === undefined) return 0
    return Number(value.length) || 0
  }

  function filteredGroups() {
    var result = []
    var groups = proxy && proxy.groups ? proxy.groups : []
    for (var i = 0; i < groups.length; i++) {
      var group = groups[i]
      if (group && group.Selectable === true && (group.Items || []).length > 0) result.push(group)
    }
    return result
  }

  function computeFilteredLogs() {
    if (logFilterText === "") return proxy.logs
    var result = []
    var entries = proxy.logs
    var keyword = logFilterText.toLowerCase()
    for (var i = 0; i < entries.length; i++) {
      var message = String((entries[i] && entries[i].Message) || "")
      if (message.toLowerCase().indexOf(keyword) !== -1) result.push(entries[i])
    }
    return result
  }

  function clampCursors() {
    var groupCount = arrayLength(selectableGroups)
    var routeCount = arrayLength(currentRoutes)
    var connectionCount = proxy ? arrayLength(proxy.connections) : 0
    groupIndex = Math.max(0, Math.min(groupIndex, groupCount - 1))
    routeIndex = Math.max(0, Math.min(routeIndex, routeCount - 1))
    connectionIndex = Math.max(0, Math.min(connectionIndex, connectionCount - 1))
  }

  function selectGroup(index) {
    var count = arrayLength(selectableGroups)
    groupIndex = Math.max(0, Math.min(index, count - 1))
    routeIndex = 0
    cursorActive = true
    contentScroll.contentY = 0
  }

  function switchTab(index) {
    activeTab = (index + 4) % 4
    cursorActive = true
    contentScroll.contentY = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dx !== 0) {
      switchTab(activeTab + dx)
      return
    }
    if (activeTab === 0 && currentRoutes.length > 0)
      routeIndex = Math.max(0, Math.min(currentRoutes.length - 1, routeIndex + dy))
    else if (activeTab === 1 && proxy.connections.length > 0)
      connectionIndex = Math.max(0, Math.min(proxy.connections.length - 1, connectionIndex + dy))
    scrollCursorIntoView()
  }

  function activateCursor() {
    if (activeTab === 0 && currentGroup && selectedRoute)
      proxy.selectOutbound(currentGroup.Tag, selectedRoute.Tag)
    else if (activeTab === 1 && selectedConnection)
      proxy.closeConnection(selectedConnection.ID)
  }

  function cycleMode() {
    if (proxy.modes.length === 0) return
    var index = proxy.modes.indexOf(proxy.currentMode)
    proxy.setMode(proxy.modes[(index + 1) % proxy.modes.length])
  }

  function openTui() {
    close()
    Quickshell.execDetached(["omarchy", "launch", "terminal", "bash", "-lc", tuiCommand])
  }

  function scrollCursorIntoView() {
    Qt.callLater(function() {
      var column = activeTab === 0 ? routeRows : (activeTab === 1 ? connectionRows : null)
      var index = activeTab === 0 ? routeIndex : connectionIndex
      if (!column || index < 0 || index >= column.children.length) return
      var item = column.children[index]
      if (!item) return
      var point = item.mapToItem(contentScroll.contentItem, 0, 0)
      var margin = Style.space(8)
      if (point.y < contentScroll.contentY + margin)
        contentScroll.contentY = Math.max(0, point.y - margin)
      else if (point.y + item.height > contentScroll.contentY + contentScroll.height - margin)
        contentScroll.contentY = Math.min(contentScroll.contentHeight - contentScroll.height,
                                          point.y + item.height + margin - contentScroll.height)
    })
  }

  function handleTextKey(text) {
    if (text === "1") switchTab(0)
    else if (text === "2") switchTab(1)
    else if (text === "3") switchTab(2)
    else if (text === "4") switchTab(3)
    else if (text === "m" || text === "M") cycleMode()
    else if (text === "u" || text === "U") {
      if (activeTab === 0 && selectedRoute) proxy.urlTest(selectedRoute.Tag)
    } else if (text === "d" && activeTab === 1 && selectedConnection) {
      proxy.closeConnection(selectedConnection.ID)
    } else if (text === "D" && activeTab === 1) {
      proxy.closeAllConnections()
    } else if ((text === "c" || text === "C") && activeTab === 2) {
      proxy.clearLogs()
    } else if (text === "/" && activeTab === 2) {
      logFilterEditing = true
    } else if (text === "r" || text === "R") {
      proxy.restart()
    } else if (text === "t" || text === "T") {
      openTui()
    }
  }

  // Suppress the shell's shorter default mark and draw one across Sinbar's
  // complete clickable area: icon plus the speed readout.
  readonly property real openPanelIndicatorWidth: 0.1
  readonly property real openPanelIndicatorHeight: 0.1
  readonly property bool barVertical: bar ? bar.vertical : false
  readonly property real speedLaneWidth: Style.space(46)
  readonly property real speedLeadingGap: Style.space(1)
  readonly property real statusBarWidth: showSpeeds
    ? Style.bar.iconSlot + speedLeadingGap + speedLaneWidth
    : Style.bar.iconSlot

  implicitWidth: barVertical ? barButton.implicitWidth : statusBarWidth
  implicitHeight: barButton.implicitHeight

  onOpenedChanged: {
    proxy.setPanelOpen(opened)
    if (opened) {
      cursorActive = false
      clampCursors()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    } else {
      logFilterEditing = false
      proxy.cancelTaildropDrop()
    }
  }
  onSelectableGroupsChanged: clampCursors()
  onCurrentRoutesChanged: clampCursors()
  onCurrentGroupChanged: routeIndex = 0
  onActiveTabChanged: {
    if (activeTab !== 2) logFilterEditing = false
    if (activeTab !== 3) proxy.cancelTaildropDrop()
  }

  Service {
    id: proxy
    settings: root.settings
  }

  Connections {
    target: proxy
    function onConnectionsChanged() { root.clampCursors() }

    // Close before launching, the same way openTui() does: while the panel
    // holds the layer-shell keyboard grab, the viewer's window maps unfocused.
    function onPreviewReady(path) {
      root.close()
      Quickshell.execDetached(["xdg-open", path])
    }
  }

  WidgetButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.barVertical ? -1 : root.statusBarWidth
    foreground: root.statusColor
    active: !proxy.connected
    activeColor: root.urgent
    tooltipText: proxy.connected
      ? "Sinbar · " + (proxy.currentMode || "sing-box") + " · right click opens TUI"
      : "Sinbar · " + (proxy.connectionError || "offline")

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.bar.iconSlot
      text: root.statusGlyph
      color: root.statusColor
      font.family: root.fontFamily
      font.pixelSize: Style.fontPx(1.1)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      opacity: proxy.connected ? 1.0 : 0.45
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.openTui()
      else if (buttonCode === Qt.MiddleButton) proxy.restart()
      else root.toggle()
    }
  }

  // Telemetry stays visually separate, while the full-size WidgetButton behind
  // it makes the icon and the speed readout one continuous click target.
  Row {
    id: speedReadout
    visible: !root.barVertical && root.showSpeeds
    anchors.left: parent.left
    anchors.leftMargin: Style.bar.iconSlot + root.speedLeadingGap
    anchors.verticalCenter: parent.verticalCenter
    width: root.speedLaneWidth

    SpeedLine {
      glyph: "↓"
      value: proxy.downlink
      tone: proxy.connected ? root.barText : root.urgent
      forceActive: !proxy.connected
    }
  }

  Rectangle {
    id: iconOpenIndicator
    readonly property int inset: Style.space(2)

    visible: opacity > 0
    opacity: root.opened ? 0.9 : 0
    color: Color.accent
    radius: Math.min(width, height) / 2
    width: root.barVertical ? Style.space(2) : Math.max(0, root.width - inset * 2)
    height: root.barVertical ? Math.max(0, root.height - inset * 2) : Style.space(2)
    x: root.barVertical
      ? ((root.bar && root.bar.position === "left") ? root.width - width - inset : inset)
      : inset
    y: root.barVertical
      ? inset
      : ((root.bar && root.bar.position === "bottom") ? inset : root.height - height - inset)
    z: 50

    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  // Drag a file from the file manager onto the bar item to send it with
  // Taildrop: the drop opens the panel on the Tailscale tab in a mode where
  // clicking a peer sends the dropped files to it.
  DropArea {
    id: dropZone
    anchors.fill: parent
    z: 100
    keys: ["text/uri-list"]

    property bool dragHover: false

    onEntered: function(drag) {
      if (drag.hasUrls) dragHover = true
      else drag.accepted = false
    }
    onExited: dragHover = false
    onDropped: function(drop) {
      dragHover = false
      if (!drop.hasUrls) return
      drop.acceptProposedAction()
      if (proxy.beginTaildropDrop(drop.urls)) {
        if (!root.opened) root.toggle()
        root.switchTab(3)
      }
    }
  }

  Rectangle {
    id: dropIndicator
    anchors.fill: parent
    visible: opacity > 0
    opacity: dropZone.dragHover ? 1 : 0
    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.14)
    border.color: root.accent
    border.width: 1
    radius: Style.cornerRadius
    z: 99

    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  KeyboardPanel {
    id: panel
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(500))
    contentHeight: panel.cappedContentHeight(Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.logFilterEditing
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) { root.handleTextKey(text) }

      Column {
        id: chrome
        anchors.fill: parent
        spacing: Style.space(10)

        PanelHero {
          id: hero
          width: parent.width
          title: proxy.version !== "" ? "sing-box " + proxy.version : "sing-box"
          meta: root.statusLabel + (Model.uptime(proxy.startedAt) !== "" ? "  ·  UP " + Model.uptime(proxy.startedAt) : "")
          detail: proxy.currentMode
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconOpacity: proxy.connected ? 1.0 : 0.45
          iconComponent: Component {
            Text {
              text: root.statusGlyph
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Math.round(Style.font.display * 0.8)
            }
          }
          trailingControl: Component {
            PanelActionButton {
              iconText: "󰑐"
              tooltipText: "Reconnect bridge (r)"
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: proxy.restart()
            }
          }
        }

        Row {
          id: trafficRail
          width: parent.width
          spacing: Style.space(8)

          TrafficLane {
            width: (parent.width - parent.spacing) / 2
            glyph: "↑"
            label: "UPLINK"
            rate: Model.formatRate(proxy.uplink)
            total: Model.formatBytes(proxy.uplinkTotal) + " total"
            tone: root.accent
          }

          TrafficLane {
            width: (parent.width - parent.spacing) / 2
            glyph: "↓"
            label: "DOWNLINK"
            rate: Model.formatRate(proxy.downlink)
            total: Model.formatBytes(proxy.downlinkTotal) + " total"
            tone: root.foreground
          }
        }

        Row {
          id: facts
          width: parent.width
          spacing: Style.space(14)

          Fact { text: proxy.connectionsOut + " connections" }
          Fact { text: Model.formatBytes(proxy.memory) + " memory" }
          Fact { text: proxy.goroutines + " goroutines" }
        }

        Text {
          visible: proxy.lastError !== "" || proxy.actionStatus !== "" || !proxy.bridgeRunning
          width: parent.width
          text: proxy.lastError !== "" ? proxy.lastError
            : (proxy.actionStatus !== "" ? proxy.actionStatus
              : "Bridge binary is unavailable. Run make build in the plugin directory.")
          color: proxy.lastError !== "" || !proxy.bridgeRunning ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Row {
          id: tabs
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: [
              { label: "1 ROUTES", count: root.currentRoutes.length },
              { label: "2 CONNS", count: proxy.connections.length },
              { label: "3 LOGS", count: proxy.logs.length },
              { label: "4 TAILSCALE", count: proxy.tailscalePeers.length }
            ]

            CursorSurface {
              required property var modelData
              required property int index
              width: (tabs.width - tabs.spacing * 3) / 4
              height: Style.space(34)
              current: root.activeTab === index
              hasCursor: false
              foreground: root.foreground

              Text {
                anchors.centerIn: parent
                text: modelData.label + (modelData.count > 0 ? "  " + modelData.count : "")
                color: root.activeTab === index ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: root.activeTab === index
                font.letterSpacing: 0.5
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.switchTab(index)
              }
            }
          }
        }

        Flickable {
          id: contentScroll
          width: parent.width
          height: Math.max(Style.space(120), chrome.height - y)
          contentWidth: width
          contentHeight: tabContent.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          interactive: contentHeight > height
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: tabContent
            width: contentScroll.width - (contentScroll.contentHeight > contentScroll.height ? Style.space(8) : 0)
            spacing: Style.space(8)

            Column {
              visible: root.activeTab === 0
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                width: parent.width
                text: "OUTBOUND GROUP"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Flow {
                width: parent.width
                spacing: Style.space(5)

                Repeater {
                  model: root.selectableGroups

                  CursorSurface {
                    required property var modelData
                    required property int index
                    width: Math.min(groupText.implicitWidth + Style.space(18), tabContent.width)
                    height: Style.space(30)
                    current: root.groupIndex === index
                    foreground: root.foreground

                    Text {
                      id: groupText
                      anchors.centerIn: parent
                      text: String(modelData.Tag || "Group")
                      color: root.groupIndex === index ? root.foreground : root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: root.groupIndex === index
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectGroup(index)
                    }
                  }
                }
              }

              PanelSeparator { width: parent.width; foreground: root.foreground }

              Column {
                id: routeRows
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: root.currentRoutes

                  RouteRow {
                    required property var modelData
                    required property int index
                    width: routeRows.width
                    route: modelData
                    rowIndex: index
                  }
                }
              }

              EmptyState {
                visible: root.currentRoutes.length === 0
                width: parent.width
                text: proxy.connected ? "No selectable outbound groups." : "Connect to the sing-box API to load routes."
              }
            }

            Column {
              visible: root.activeTab === 1
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                height: closeAllButton.implicitHeight

                PanelSectionHeader {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "ACTIVE CONNECTIONS"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                PanelActionButton {
                  id: closeAllButton
                  anchors.right: parent.right
                  iconText: "󰅖"
                  tooltipText: "Close all connections (D)"
                  foreground: root.foreground
                  hoverColor: root.urgent
                  fontFamily: root.fontFamily
                  enabled: proxy.connections.length > 0 && !proxy.busy
                  onClicked: proxy.closeAllConnections()
                }
              }

              Column {
                id: connectionRows
                width: parent.width
                spacing: Style.space(4)

                Repeater {
                  model: proxy.connections

                  ConnectionRow {
                    required property var modelData
                    required property int index
                    width: connectionRows.width
                    connection: modelData
                    rowIndex: index
                  }
                }
              }

              EmptyState {
                visible: proxy.connections.length === 0
                width: parent.width
                text: proxy.connected ? "No active connections." : "Connection stream is offline."
              }
            }

            Column {
              visible: root.activeTab === 3
              width: parent.width
              spacing: Style.space(8)

              PanelSectionHeader {
                width: parent.width
                text: "TAILSCALE · " + String(proxy.tailscaleState || "Unavailable").toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              CursorSurface {
                visible: proxy.taildropPickMode
                width: parent.width
                implicitHeight: Style.space(40)
                current: true
                foreground: root.accent

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    width: parent.width - cancelDropButton.width - parent.spacing
                    anchors.verticalCenter: parent.verticalCenter
                    text: "⇢ Sending " + proxy.pendingTaildropFiles.length
                      + (proxy.pendingTaildropFiles.length === 1 ? " file" : " files")
                      + " · pick a peer, Esc to cancel"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  PanelActionButton {
                    id: cancelDropButton
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: "󰅖"
                    tooltipText: "Cancel Taildrop"
                    foreground: root.foreground
                    hoverColor: root.urgent
                    fontFamily: root.fontFamily
                    onClicked: proxy.cancelTaildropDrop()
                  }
                }
              }

              Text {
                width: parent.width
                text: proxy.tailscaleSelf
                  ? String(proxy.tailscaleSelf.hostName || "This device") + "  ·  "
                    + String((proxy.tailscaleSelf.tailscaleIPs || ["—"])[0]) + "  ·  " + proxy.tailscaleNetwork
                  : (proxy.tailscaleEndpoint === "" ? "No matching Tailscale endpoint." : "Waiting for node information…")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }

              Row {
                spacing: Style.space(6)
                PanelActionButton {
                  iconText: "󰖟"
                  tooltipText: "Open Tailscale login"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  visible: proxy.tailscaleAuthUrl !== ""
                  onClicked: Quickshell.execDetached(["omarchy-launch-browser", proxy.tailscaleAuthUrl])
                }
                PanelActionButton {
                  iconText: "󰍃"
                  tooltipText: "Clear exit node"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  visible: proxy.tailscaleExitNode !== null
                  onClicked: proxy.clearTailscaleExitNode()
                }
              }

              // Files other devices have sent us. Rendered only when the inbox
              // is non-empty — the panel is compact and an always-present empty
              // section would just push the peer list down.
              Column {
                id: inboxSection
                visible: proxy.taildropInbox.length > 0
                width: parent.width
                spacing: Style.space(4)

                // The whole header toggles, not just the chevron — the button is
                // declared last so it stays above the full-width MouseArea and
                // keeps its own hover state and tooltip.
                Item {
                  width: parent.width
                  height: inboxToggle.implicitHeight

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.inboxCollapsed = !root.inboxCollapsed
                  }

                  PanelSectionHeader {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "RECEIVED FILES · " + proxy.taildropInbox.length
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                  }

                  PanelActionButton {
                    id: inboxToggle
                    anchors.right: parent.right
                    iconText: root.inboxCollapsed ? "󰅂" : "󰅀"
                    tooltipText: root.inboxCollapsed ? "Show received files" : "Hide received files"
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                    onClicked: root.inboxCollapsed = !root.inboxCollapsed
                  }
                }

                Column {
                  id: inboxRows
                  visible: !root.inboxCollapsed
                  width: parent.width
                  spacing: Style.space(4)

                  Repeater {
                    model: proxy.taildropInbox

                    CursorSurface {
                      required property var modelData
                      width: inboxRows.width
                      implicitHeight: Style.space(52)
                      foreground: root.foreground

                      // Clicking the row opens the file with the desktop's
                      // default handler. Declared before the Row so the action
                      // buttons stay above it and keep their own clicks.
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        enabled: !proxy.busy
                        onClicked: proxy.previewTaildropFile(modelData)
                      }

                      Row {
                        anchors.fill: parent
                        anchors.leftMargin: Style.space(10)
                        anchors.rightMargin: Style.space(8)
                        spacing: Style.space(8)

                        Column {
                          width: parent.width - saveFileButton.width - discardFileButton.width - parent.spacing * 2
                          anchors.verticalCenter: parent.verticalCenter
                          Text { width: parent.width; text: String(modelData.name || "File"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                          Text { width: parent.width; text: Model.taildropSubtitle(modelData); color: root.dim; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                        }

                        PanelActionButton {
                          id: saveFileButton
                          iconText: "󰇚"
                          tooltipText: "Save to ~/Downloads"
                          foreground: root.foreground
                          fontFamily: root.fontFamily
                          enabled: !proxy.busy
                          onClicked: proxy.saveTaildropFile(modelData)
                        }
                        PanelActionButton {
                          id: discardFileButton
                          iconText: "󰩹"
                          tooltipText: "Discard without saving"
                          foreground: root.foreground
                          hoverColor: root.urgent
                          fontFamily: root.fontFamily
                          enabled: !proxy.busy
                          onClicked: proxy.deleteTaildropFile(modelData)
                        }
                      }
                    }
                  }
                }
              }

              Repeater {
                model: proxy.tailscalePeers

                CursorSurface {
                  id: peerRow
                  required property var modelData
                  readonly property bool pickTarget: proxy.taildropPickMode && proxy.taildropEligible(modelData)
                  width: tabContent.width
                  implicitHeight: Style.space(52)
                  current: modelData.exitNode === true || pickTarget
                  opacity: proxy.taildropPickMode && !pickTarget ? 0.4 : 1
                  foreground: root.foreground

                  Row {
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(8)
                    spacing: Style.space(8)
                    Column {
                      width: parent.width
                        - (sendButton.visible ? sendButton.width + parent.spacing : 0)
                        - (copyButton.visible ? copyButton.width + parent.spacing : 0)
                        - (exitButton.visible ? exitButton.width + parent.spacing : 0)
                      anchors.verticalCenter: parent.verticalCenter
                      Text { width: parent.width; text: String(modelData.hostName || modelData.dnsName || "Peer"); color: root.foreground; font.family: root.fontFamily; font.pixelSize: Style.font.body; elide: Text.ElideRight }
                      Text { width: parent.width; text: String((modelData.tailscaleIPs || ["—"])[0]) + (modelData.online ? "  ·  online" : "  ·  offline"); color: modelData.online ? root.dim : root.faint; font.family: root.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                    }
                    PanelActionButton {
                      id: sendButton
                      iconText: "󰒊"
                      tooltipText: "Send files with Taildrop"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      visible: proxy.tailscaleCanShareFiles && modelData.canReceiveFiles === true
                      enabled: modelData.online === true && !proxy.busy
                      onClicked: proxy.chooseTaildropFiles(modelData)
                    }
                    PanelActionButton {
                      id: copyButton
                      iconText: "󰆏"
                      tooltipText: "Copy Tailscale IP"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      enabled: (modelData.tailscaleIPs || []).length > 0
                      onClicked: Quickshell.execDetached(["wl-copy", String(modelData.tailscaleIPs[0])])
                    }
                    PanelActionButton {
                      id: exitButton
                      iconText: "󰒍"
                      tooltipText: "Use as exit node"
                      foreground: root.foreground
                      fontFamily: root.fontFamily
                      visible: modelData.exitNodeOption === true
                      enabled: modelData.online === true && !proxy.busy
                      onClicked: proxy.setTailscaleExitNode(modelData)
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    z: 10
                    visible: proxy.taildropPickMode
                    enabled: proxy.taildropPickMode
                    hoverEnabled: true
                    cursorShape: peerRow.pickTarget ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                    onClicked: proxy.sendTaildropTo(peerRow.modelData)
                  }
                }
              }

              EmptyState {
                visible: proxy.tailscalePeers.length === 0
                width: parent.width
                text: proxy.tailscaleEndpoint === ""
                  ? "Tailscale is not connected."
                  : "No Tailscale peers available."
              }
            }

            Column {
              visible: root.activeTab === 2
              width: parent.width
              spacing: Style.space(6)

              Item {
                width: parent.width
                height: clearLogsButton.implicitHeight

                PanelSectionHeader {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "LIVE LOG"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                PanelActionButton {
                  id: clearLogsButton
                  anchors.right: parent.right
                  iconText: "󰃢"
                  tooltipText: "Clear logs (c)"
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  enabled: !proxy.busy
                  onClicked: proxy.clearLogs()
                }
              }

              TextField {
                id: logFilterField
                visible: root.logFilterEditing
                width: parent.width
                placeholderText: "Filter logs… (Enter to confirm, Esc to cancel)"
                foreground: root.foreground
                font.family: root.fontFamily
                horizontalPadding: Style.spacing.controlGap
                verticalPadding: Style.spacing.controlPaddingY
                text: root.logFilterEditing ? root.logFilterText : ""

                onTextChanged: if (root.logFilterEditing && text !== root.logFilterText) root.logFilterText = text
                onAccepted: root.logFilterEditing = false
                Keys.onEscapePressed: { text = ""; root.logFilterText = ""; root.logFilterEditing = false }

                onVisibleChanged: if (visible) Qt.callLater(forceActiveFocus)
              }

              Text {
                id: logFilterChip
                visible: !root.logFilterEditing && root.logFilterText !== ""
                width: parent.width
                text: "⌕ “" + root.logFilterText + "” · " + root.filteredLogs.length
                  + (root.filteredLogs.length === 1 ? " match" : " matches")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Repeater {
                model: root.filteredLogs

                LogRow {
                  required property var modelData
                  width: tabContent.width
                  entry: modelData
                }
              }

              EmptyState {
                visible: root.filteredLogs.length === 0
                width: parent.width
                text: !proxy.connected ? "Log stream is offline."
                  : (proxy.logs.length === 0 ? "Waiting for log messages…"
                    : "No log lines match “" + root.logFilterText + "”.")
              }
            }
          }
        }
      }
    }
  }

  component TrafficLane: BorderSurface {
    id: lane
    property string glyph: ""
    property string label: ""
    property string rate: ""
    property string total: ""
    property color tone: root.foreground

    height: Style.space(72)
    color: Qt.rgba(tone.r, tone.g, tone.b, 0.055)
    borderSpec: Border.flat(Qt.rgba(tone.r, tone.g, tone.b, 0.18), 1)
    radius: Style.cornerRadius

    Text {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(12)
      anchors.top: parent.top
      anchors.topMargin: Style.space(10)
      text: lane.glyph
      color: lane.tone
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      font.bold: true
    }

    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(38)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)

      Text {
        width: parent.width
        text: lane.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
      }
      Text {
        width: parent.width
        text: lane.rate
        color: lane.tone
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: lane.total
        color: root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  // Bar-item speed row: a dimmed direction arrow plus a value that lights up
  // in its tone color only while that direction is actually moving bytes,
  // so an idle link reads as quiet instead of shouting a static number.
  component SpeedLine: Row {
    id: speedLine
    property real value: 0
    property string glyph: "↑"
    property color tone: root.foreground
    property bool forceActive: false
    readonly property bool active: value > 0 || forceActive

    width: root.speedLaneWidth
    spacing: Style.space(1)

    Text {
      id: arrowGlyph
      width: Style.space(10)
      text: speedLine.glyph
      color: root.barDim
      font.family: root.fontFamily
      font.pixelSize: Style.fontPx(0.85)
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }

    Text {
      width: speedLine.width - arrowGlyph.width - speedLine.spacing
      text: Model.formatRateFixed(speedLine.value)
      color: speedLine.active ? speedLine.tone : root.barFaint
      font.family: root.fontFamily
      font.pixelSize: Style.fontPx(0.8)
      font.bold: speedLine.active
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight

      Behavior on color { ColorAnimation { duration: 160 } }
    }
  }

  component Fact: Text {
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  component RouteRow: CursorSurface {
    id: routeRow
    property var route: null
    property int rowIndex: 0
    readonly property bool selected: root.currentGroup && route && String(root.currentGroup.Selected || "") === String(route.Tag || "")
    readonly property int delay: Number(route ? route.TestDelay : 0)
    readonly property color delayTone: delay <= 0 ? root.faint : (delay < 150 ? root.accent : (delay < 500 ? root.foreground : root.urgent))

    hasCursor: root.cursorActive && root.activeTab === 0 && root.routeIndex === rowIndex
    current: selected
    foreground: root.foreground
    implicitHeight: Style.space(46)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: { root.cursorActive = true; root.routeIndex = routeRow.rowIndex }
      onClicked: if (root.currentGroup && routeRow.route) proxy.selectOutbound(root.currentGroup.Tag, routeRow.route.Tag)
    }

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        width: Style.space(18)
        text: routeRow.selected ? "●" : "○"
        color: routeRow.selected ? root.accent : root.faint
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(18) - delayText.width - testButton.width - parent.spacing * 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          width: parent.width
          text: routeRow.route ? String(routeRow.route.Tag || "Unnamed route") : "Unnamed route"
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: routeRow.selected
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: routeRow.route ? String(routeRow.route.Type || "outbound") : "outbound"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: delayText
        width: Style.space(62)
        text: Model.routeDelay(routeRow.delay)
        color: routeRow.delayTone
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }

      PanelActionButton {
        id: testButton
        iconText: "󰓅"
        tooltipText: "Test latency (u)"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: !proxy.busy
        anchors.verticalCenter: parent.verticalCenter
        onClicked: if (routeRow.route) proxy.urlTest(routeRow.route.Tag)
      }
    }
  }

  component ConnectionRow: CursorSurface {
    id: connectionRow
    property var connection: null
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.activeTab === 1 && root.connectionIndex === rowIndex
    foreground: root.foreground
    implicitHeight: Style.space(58)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.ArrowCursor
      onEntered: { root.cursorActive = true; root.connectionIndex = connectionRow.rowIndex }
    }

    Row {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Text {
        width: Style.space(22)
        text: connectionRow.connection && String(connectionRow.connection.Network) === "udp" ? "󰖟" : "󰌘"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(22) - transferText.width - closeButton.width - parent.spacing * 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          width: parent.width
          text: Model.connectionTitle(connectionRow.connection)
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: Model.shortProcess(connectionRow.connection ? connectionRow.connection.ProcessPath : "")
                + "  →  " + String(connectionRow.connection ? connectionRow.connection.Outbound || "direct" : "direct")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        id: transferText
        width: Style.space(82)
        text: "↑" + Model.formatBytes(connectionRow.connection ? connectionRow.connection.UplinkTotal : 0)
              + "\n↓" + Model.formatBytes(connectionRow.connection ? connectionRow.connection.DownlinkTotal : 0)
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }

      PanelActionButton {
        id: closeButton
        iconText: "󰅖"
        tooltipText: "Close connection (d)"
        foreground: root.foreground
        hoverColor: root.urgent
        fontFamily: root.fontFamily
        enabled: !proxy.busy
        anchors.verticalCenter: parent.verticalCenter
        onClicked: if (connectionRow.connection) proxy.closeConnection(connectionRow.connection.ID)
      }
    }
  }

  component LogRow: Row {
    id: logRow
    property var entry: null
    readonly property int level: Number(entry ? entry.Level : 4)
    readonly property color tone: level <= 2 ? root.urgent : (level === 3 ? root.accent : (level >= 5 ? root.faint : root.dim))

    spacing: Style.space(8)
    height: Math.max(levelText.implicitHeight, messageText.implicitHeight) + Style.space(4)

    Text {
      id: levelText
      width: Style.space(48)
      text: Model.logLevelName(logRow.level)
      color: logRow.tone
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: logRow.level <= 3
      horizontalAlignment: Text.AlignRight
    }

    Text {
      id: messageText
      width: logRow.width - levelText.width - logRow.spacing
      textFormat: Text.StyledText
      text: logRow.entry ? (logRow.entry.MessageRich || logRow.entry.Message || "") : ""
      color: logRow.tone
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WrapAnywhere
    }
  }

  component EmptyState: Text {
    topPadding: Style.space(24)
    bottomPadding: Style.space(24)
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
  }
}
