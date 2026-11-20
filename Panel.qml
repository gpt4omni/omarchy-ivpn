import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.gpt4omni.ivpn"
  ipcTarget: moduleName
  manageIpc: false

  property int cursorIndex: -1
  property bool cursorActive: false
  property bool confirmStartDaemon: false

  readonly property color foreground: root.bar ? root.bar.foreground : Color.popups.text
  readonly property color background: Color.popups.background
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color urgent: root.bar ? root.bar.urgent : Color.urgent
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
  readonly property color iconDim: Util.alpha(foreground, 0.55)

  readonly property bool showCountryInBar: !root.settings || root.settings.showCountryInBar !== false
  readonly property string barCountryCode: ivpn.connected ? ivpn.activeCountryCode() : ""

  readonly property bool iconConnected: ivpn.state === "connected" && ivpn.connected
  readonly property bool iconPaused: ivpn.state === "paused" && ivpn.paused
  readonly property bool iconPulse: ivpn.state === "checking" || ivpn.state === "connecting" || ivpn.actionBusy
  readonly property bool iconUrgent: ["missing-client", "daemon-down", "logged-out", "error"].indexOf(ivpn.state) !== -1
  readonly property string iconStatus: {
    if (ivpn.state === "checking" || ivpn.state === "connecting") return "connecting"
    if (iconUrgent) return "urgent"
    if (iconPaused) return "paused"
    if (iconConnected) return "connected"
    return "disconnected"
  }
  readonly property color barIconColor: (iconStatus === "connected" || iconStatus === "connecting" || iconStatus === "paused")
    ? foreground : iconDim

  readonly property bool dropdownOpen: locationDropdown.popupOpen || exitDropdown.popupOpen
    || protocolDropdown.popupOpen || antiTrackerDropdown.popupOpen
  readonly property bool textInputFocused: loginField.activeFocus

  readonly property int targetCount: {
    if (ivpn.state === "daemon-down") return 1
    if (!ivpn.operational) return 0
    return ivpn.firewallEnabled ? 7 : 6
  }

  readonly property var locationOptions: {
    var list = [
      { value: "__fastest__", label: "Fastest server", description: "Automatically pick lowest-latency location" },
      { value: "__random__", label: "Random server", description: "Connect to a random IVPN location" }
    ]
    var servers = ivpn.servers || []
    for (var i = 0; i < servers.length; i++) {
      list.push(servers[i])
    }
    return list
  }

  readonly property var exitOptions: {
    var list = [
      { value: "", label: "Off (Single-hop)", description: "Standard direct VPN tunnel" }
    ]
    var entryServer = ivpn.serverByHost(ivpn.selectedLocation)
    var entryCc = entryServer ? entryServer.countryCode : ""
    var servers = ivpn.servers || []
    for (var i = 0; i < servers.length; i++) {
      if (entryCc && servers[i].countryCode && servers[i].countryCode === entryCc) continue
      list.push(servers[i])
    }
    return list
  }

  readonly property var protocolOptions: [
    { value: "wg", label: "WireGuard (recommended)" },
    { value: "ovpn", label: "OpenVPN" }
  ]

  readonly property var antiTrackerOptions: Model.ANTITRACKER_PRESETS

  implicitWidth: barButton.implicitWidth
  implicitHeight: barButton.implicitHeight

  Service {
    id: ivpn
    settings: root.settings
    pollingPaused: root.dropdownOpen || root.textInputFocused || root.confirmStartDaemon
  }

  function heroTitle() {
    if (ivpn.state === "missing-client") return "IVPN CLI missing"
    if (ivpn.state === "daemon-down") return "IVPN service stopped"
    if (ivpn.state === "logged-out") return "Login required"
    if (ivpn.actionStatus !== "") return ivpn.actionStatus.replace(/…$/, "")
    if (ivpn.state === "paused") return "IVPN paused"
    if (ivpn.state === "connected") {
      var loc = ivpn.activeServerLabel()
      if (ivpn.multiHop && ivpn.countryCode && ivpn.exitCountryCode) {
        return "IVPN · " + ivpn.countryCode + " → " + ivpn.exitCountryCode
      }
      return loc ? ("IVPN · " + loc.replace(/^[^·]+·\s*/, "")) : "IVPN connected"
    }
    if (ivpn.state === "connecting") return "IVPN connecting"
    if (ivpn.state === "disconnected") return "IVPN disconnected"
    return "IVPN"
  }

  function heroMeta() {
    if (ivpn.actionStatus !== "") return ivpn.actionStatus.replace(/…$/, "").toUpperCase()
    if (ivpn.state === "missing-client") return "CLIENT REQUIRED"
    if (ivpn.state === "daemon-down") return "DAEMON STOPPED"
    if (ivpn.state === "logged-out") return "NOT LOGGED IN"
    var proto = (ivpn.activeProtocol || ivpn.protocol) === "ovpn" ? "OPENVPN" : "WIREGUARD"
    if (ivpn.state === "connected") return "CONNECTED · " + proto
    if (ivpn.state === "paused") return "PAUSED" + (ivpn.pausedTill ? (" · UNTIL " + ivpn.pausedTill.toUpperCase()) : "")
    if (ivpn.state === "connecting" || ivpn.actionBusy) return "WORKING"
    if (ivpn.state === "disconnected") return "DISCONNECTED"
    return String(ivpn.state || "unknown").toUpperCase()
  }

  function heroDetail() {
    var badges = []
    if (ivpn.multiHop) badges.push("MULTI-HOP")
    if (ivpn.firewallEnabled) badges.push("KILL SWITCH")
    return badges.join(" · ")
  }

  function barTooltip() {
    if (ivpn.state === "connected") {
      var parts = ["IVPN"]
      var lbl = ivpn.activeServerLabel()
      if (lbl) parts.push(lbl)
      if (ivpn.multiHop && ivpn.exitCountryCode) parts.push("Exit: " + ivpn.exitCountryCode)
      parts.push((ivpn.activeProtocol || ivpn.protocol) === "ovpn" ? "OpenVPN" : "WireGuard")
      if (ivpn.firewallEnabled) parts.push("Kill Switch ON")
      return parts.join(" · ")
    }
    return "IVPN · " + heroMeta().toLowerCase()
  }

  function restoreLocationBinding() {
    locationDropdown.value = Qt.binding(function() { return ivpn.selectedLocation })
  }
  function restoreExitBinding() {
    exitDropdown.value = Qt.binding(function() { return ivpn.selectedExit })
  }
  function restoreProtocolBinding() {
    protocolDropdown.value = Qt.binding(function() { return ivpn.protocol })
  }
  function restoreAntiTrackerBinding() {
    antiTrackerDropdown.value = Qt.binding(function() { return ivpn.antiTracker })
  }

  function requestStartDaemon() {
    confirmStartDaemon = true
    daemonConfirm.selectedIndex = 1
    Qt.callLater(function() { confirmKeys.forceActiveFocus() })
  }

  function closeConfirm() {
    confirmStartDaemon = false
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function setCursor(index) {
    if (targetCount <= 0) {
      cursorActive = false
      cursorIndex = -1
      return
    }
    cursorActive = true
    cursorIndex = Math.max(0, Math.min(targetCount - 1, index))
  }

  function ensureCursorVisible() {
    if (!opened || !cursorActive || cursorIndex < 0) return
    var item = null
    if (ivpn.state === "daemon-down") item = daemonRecoveryRow
    else if (cursorIndex === 0) item = heroHost
    else if (cursorIndex === 1) item = locationDropdown
    else if (cursorIndex === 2) item = exitDropdown
    else if (cursorIndex === 3) item = protocolDropdown
    else if (cursorIndex === 4) item = antiTrackerDropdown
    else if (cursorIndex === 5) item = firewallToggle
    else if (cursorIndex === 6) item = allowLanToggle
    if (!item || !item.visible) return
    var pt = item.mapToItem(panelContent, 0, 0)
    var margin = Style.spacing.controlGap
    if (pt.y - margin < panelFlick.contentY)
      panelFlick.contentY = Math.max(0, pt.y - margin)
    else if (pt.y + item.height + margin > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(Math.max(0, panelFlick.contentHeight - panelFlick.height),
        pt.y + item.height + margin - panelFlick.height)
  }

  function moveCursor(dx, dy) {
    if (!cursorActive) {
      setCursor(0)
      return
    }
    if (dy !== 0) setCursor(cursorIndex + dy)
    else if (dx !== 0 && cursorIndex > 0) activateCursor()
  }

  function activateCursor() {
    if (!cursorActive || cursorIndex < 0 || ivpn.actionBusy) return
    if (ivpn.state === "daemon-down") { requestStartDaemon(); return }
    if (cursorIndex === 0) ivpn.toggleVpn()
    else if (cursorIndex === 1) locationDropdown.open()
    else if (cursorIndex === 2) exitDropdown.open()
    else if (cursorIndex === 3) protocolDropdown.open()
    else if (cursorIndex === 4) antiTrackerDropdown.open()
    else if (cursorIndex === 5) ivpn.toggleFirewall()
    else if (cursorIndex === 6) ivpn.toggleAllowLan()
  }

  function close() {
    locationDropdown.close()
    exitDropdown.close()
    protocolDropdown.close()
    antiTrackerDropdown.close()
    confirmStartDaemon = false
    controller.hide()
  }

  onTargetCountChanged: {
    if (targetCount <= 0) { cursorActive = false; cursorIndex = -1 }
    else if (cursorIndex >= targetCount) cursorIndex = targetCount - 1
  }

  onCursorIndexChanged: Qt.callLater(ensureCursorVisible)

  onDropdownOpenChanged: if (!dropdownOpen && opened && !textInputFocused && !confirmStartDaemon)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursorIndex = -1
    confirmStartDaemon = false
    ivpn.refresh(true)
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  IpcHandler {
    target: root.moduleName
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { ivpn.refresh(true); return "ok" }
    function connect(): string { return ivpn.connect() ? "ok" : "unavailable" }
    function connectFastest(): string { return ivpn.connectFastest() ? "ok" : "unavailable" }
    function disconnect(): string { return ivpn.disconnect() ? "ok" : "unavailable" }
    function toggleVpn(): string { return ivpn.toggleVpn() ? "ok" : "unavailable" }
    function toggleFirewall(): string { return ivpn.toggleFirewall() ? "ok" : "unavailable" }
    function status(): string { return ivpn.statusJson() }
  }

  WidgetButton {
    id: barButton
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.barTooltip()
    fixedWidth: (root.bar && root.bar.vertical) ? -1 : Math.max(Style.bar.iconSlot, barRow.implicitWidth + Style.space(10))
    fixedHeight: (root.bar && root.bar.vertical) ? Style.bar.iconSlot : -1

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: Style.space(4)

      ShieldIcon {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: Style.bar.iconCanvas
        color: root.barIconColor
        indicatorColor: root.foreground
        dimColor: root.iconDim
        badgeColor: root.urgent
        backgroundColor: root.bar ? root.bar.background : Color.bar.background
        fontFamily: root.fontFamily
        status: root.iconStatus
        pulse: root.iconPulse
      }

      Text {
        visible: root.showCountryInBar && root.barCountryCode !== "" && !(root.bar && root.bar.vertical)
        anchors.verticalCenter: parent.verticalCenter
        text: root.barCountryCode
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Math.max(9, Style.font.caption)
        font.bold: true
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) {
        if (!ivpn.toggleVpn()) root.open()
      } else if (buttonCode === Qt.MiddleButton) {
        ivpn.refresh(true)
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: popup
    anchorItem: barButton
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(390))
    contentHeight: popup.fittedContentHeight(panelContent.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.dropdownOpen || root.textInputFocused || root.confirmStartDaemon
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        var key = text.toLowerCase()
        if (key === "t" && ivpn.operational) ivpn.toggleVpn()
        else if (key === "f" && ivpn.operational) ivpn.connectFastest()
        else if (key === "k" && ivpn.daemonRunning) ivpn.toggleFirewall()
        else if (key === "r") { ivpn.actionError = ""; ivpn.refresh(true) }
      }
    }

    Flickable {
      id: panelFlick
      anchors.fill: parent
      contentWidth: width
      contentHeight: panelContent.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      flickableDirection: Flickable.VerticalFlick
      interactive: contentHeight > height
      ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

      Column {
        id: panelContent
        width: panelFlick.width
        spacing: Style.spacing.panelGap

        // --- HERO HEADER ---
        Item {
          id: heroHost
          width: parent.width
          implicitHeight: hero.implicitHeight

          PanelHero {
            id: hero
            width: parent.width
            title: root.heroTitle()
            meta: root.heroMeta()
            detail: root.heroDetail()
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: 1.0
            iconComponent: Component {
              ShieldIcon {
                iconSize: Style.font.display
                color: root.barIconColor
                indicatorColor: root.foreground
                dimColor: root.iconDim
                badgeColor: root.urgent
                backgroundColor: root.background
                fontFamily: root.fontFamily
                status: root.iconStatus
                pulse: root.iconPulse
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: ivpn.operational
                checked: ivpn.connected && !ivpn.paused
                busy: ivpn.actionBusy || ivpn.state === "connecting"
                interactive: !ivpn.actionBusy
                hasCursor: root.cursorActive && root.cursorIndex === 0
                foreground: hero.foreground
                onHovered: function(hovered) { if (hovered) root.setCursor(0) }
                onToggled: ivpn.toggleVpn()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: ivpn.paused ? "Resume IVPN" : (ivpn.connected ? "Disconnect IVPN" : "Connect IVPN")
                  fontFamily: root.fontFamily
                }
              }
            }
          }
        }

        // --- ACTION / ERROR MESSAGE ---
        Text {
          visible: ivpn.actionStatus !== "" || ivpn.actionError !== "" || (ivpn.statusError !== "" && ivpn.state === "error")
          width: parent.width
          text: ivpn.actionStatus !== "" ? ivpn.actionStatus
            : (ivpn.actionError !== "" ? ivpn.actionError : ivpn.statusError)
          color: ivpn.actionStatus !== "" ? root.dim : root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        // --- LIVE CONNECTION INFO CARD ---
        CursorSurface {
          visible: ivpn.operational && (ivpn.connected || ivpn.paused)
          width: parent.width
          implicitHeight: connInfoCol.implicitHeight + Style.spacing.rowPaddingX * 1.4
          foreground: root.foreground

          Column {
            id: connInfoCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.rowPaddingX
            spacing: Style.spacing.xs

            Text {
              width: parent.width
              text: {
                var entry = ivpn.activeServerLabel() || ivpn.hostname || "Connected"
                if (ivpn.multiHop) {
                  var exitL = ivpn.activeExitLabel() || ivpn.exitHostname
                  return entry + "  →  " + exitL
                }
                return entry
              }
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: {
                var bits = []
                if (ivpn.hostname) bits.push(ivpn.hostname)
                if (ivpn.localIp) bits.push("IP " + ivpn.localIp)
                if (ivpn.connectedSince) {
                  var tm = ivpn.connectedSince.match(/\b(\d{2}:\d{2}:\d{2})\b/)
                  bits.push(tm ? ("Since " + tm[1]) : ivpn.connectedSince)
                }
                return bits.join(" · ")
              }
              visible: text !== ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              text: {
                var bits = []
                if (ivpn.dns) bits.push("DNS: " + ivpn.dns)
                if (ivpn.antiTrackerSummary) bits.push("AntiTracker: " + ivpn.antiTrackerSummary)
                return bits.join(" · ")
              }
              visible: text !== ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        // --- QUICK ACTIONS BAR ---
        Row {
          id: quickActionsRow
          visible: ivpn.operational
          width: parent.width
          spacing: Style.spacing.sm
          readonly property int btnCount: ivpn.guiInstalled ? 3 : 2
          readonly property real btnWidth: (width - spacing * (btnCount - 1)) / btnCount

          Button {
            width: quickActionsRow.btnWidth
            text: "Fastest"
            bordered: true
            enabled: !ivpn.actionBusy
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            tooltipText: "Connect to the lowest-latency IVPN server (shortcut: f)"
            onClicked: ivpn.connectFastest()
          }

          Button {
            width: quickActionsRow.btnWidth
            text: ivpn.paused ? "Resume" : (ivpn.connected ? "Pause 15m" : "Random")
            bordered: true
            enabled: !ivpn.actionBusy
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            tooltipText: ivpn.paused ? "Resume VPN connection"
              : (ivpn.connected ? "Temporarily pause VPN for 15 minutes" : "Connect to a random server")
            onClicked: {
              if (ivpn.paused) ivpn.resume()
              else if (ivpn.connected) ivpn.pause(15)
              else ivpn.connectTo("__random__")
            }
          }

          Button {
            visible: ivpn.guiInstalled
            width: quickActionsRow.btnWidth
            text: "Open App"
            bordered: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            tooltipText: "Launch the full IVPN desktop app"
            onClicked: { ivpn.openGui(); root.close() }
          }
        }

        // --- MISSING CLIENT CARD ---
        CursorSurface {
          visible: ivpn.state === "missing-client"
          width: parent.width
          implicitHeight: missingCol.implicitHeight + Style.spacing.rowPaddingX * 1.4
          foreground: root.foreground

          Column {
            id: missingCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.rowPaddingX
            spacing: Style.spacing.labelGap

            Text {
              width: parent.width
              text: "ivpn CLI package is required"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Install the official ivpn AUR package (and optional ivpn-ui for the desktop app), then click Refresh."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }

        // --- LOGIN CARD ---
        CursorSurface {
          visible: ivpn.state === "logged-out"
          width: parent.width
          implicitHeight: loginCol.implicitHeight + Style.spacing.rowPaddingX * 1.6
          foreground: root.foreground

          Column {
            id: loginCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.rowPaddingX
            spacing: Style.spacing.sm

            Text {
              width: parent.width
              text: "Sign in with your IVPN Account ID"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }

            Text {
              width: parent.width
              text: "Enter your Account ID below (e.g. i-XXXX-XXXX-XXXX) to activate IVPN on this device."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            TextField {
              id: loginField
              width: parent.width
              placeholderText: "i-XXXX-XXXX-XXXX"
              foreground: root.foreground
              font.family: root.fontFamily
              onAccepted: {
                if (ivpn.login(loginField.text)) loginField.text = ""
              }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.sm

              Button {
                width: ivpn.guiInstalled ? (parent.width - parent.spacing) * 0.55 : parent.width
                text: "Log In"
                bordered: true
                selected: true
                enabled: !ivpn.actionBusy && loginField.text.trim().length >= 6
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: {
                  if (ivpn.login(loginField.text)) loginField.text = ""
                }
              }

              Button {
                visible: ivpn.guiInstalled
                width: (parent.width - parent.spacing) * 0.45
                text: "Open App"
                bordered: true
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: { ivpn.openGui(); root.close() }
              }
            }
          }
        }

        // --- DAEMON RECOVERY ROW ---
        CursorSurface {
          id: daemonRecoveryRow
          visible: ivpn.state === "daemon-down"
          width: parent.width
          implicitHeight: daemonCol.implicitHeight + Style.spacing.rowPaddingX * 1.4
          hasCursor: root.cursorActive && root.cursorIndex === 0
          foreground: root.foreground

          Column {
            id: daemonCol
            anchors.left: parent.left
            anchors.right: daemonChevron.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.controlGap
            spacing: Style.spacing.labelGap

            Text {
              width: parent.width
              text: "Start IVPN service"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
            }
            Text {
              width: parent.width
              text: "Enable and start ivpn-service with administrator authentication."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            id: daemonChevron
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.rowPaddingX
            anchors.verticalCenter: parent.verticalCenter
            text: "›"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            enabled: !ivpn.actionBusy
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) root.setCursor(0)
            onClicked: root.requestStartDaemon()
          }
        }

        PanelSeparator {
          visible: ivpn.operational
          foreground: root.foreground
        }

        // --- ROUTING SECTION ---
        Column {
          visible: ivpn.operational
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(routingHeader.implicitHeight, serverCountLabel.implicitHeight)
            PanelSectionHeader {
              id: routingHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "ROUTING"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }
            PanelSectionHeader {
              id: serverCountLabel
              visible: ivpn.servers.length > 0
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: ivpn.servers.length + " LOCATIONS"
              foreground: root.dim
              fontFamily: root.fontFamily
            }
          }

          SearchableDropdown {
            id: locationDropdown
            width: parent.width
            label: "COUNTRY / CITY"
            placeholderText: "Search country, city, code, ISP…"
            emptyText: "No matching IVPN servers"
            value: ivpn.selectedLocation
            options: root.locationOptions
            enabled: !ivpn.actionBusy
            opacity: enabled ? 1.0 : 0.5
            hasCursor: root.cursorActive && root.cursorIndex === 1
            foreground: root.foreground
            background: root.background
            fontFamily: root.fontFamily
            onHovered: function(hovered) { if (hovered && !ivpn.actionBusy) root.setCursor(1) }
            onChanged: function(value) {
              ivpn.connectTo(value)
              Qt.callLater(root.restoreLocationBinding)
            }
          }

          SearchableDropdown {
            id: exitDropdown
            width: parent.width
            label: "MULTI-HOP EXIT"
            placeholderText: "Search exit country or city…"
            emptyText: "No matching exit servers"
            value: ivpn.selectedExit
            options: root.exitOptions
            enabled: !ivpn.actionBusy
            opacity: enabled ? 1.0 : 0.5
            hasCursor: root.cursorActive && root.cursorIndex === 2
            foreground: root.foreground
            background: root.background
            fontFamily: root.fontFamily
            onHovered: function(hovered) { if (hovered && !ivpn.actionBusy) root.setCursor(2) }
            onChanged: function(value) {
              ivpn.setExitServer(value)
              Qt.callLater(root.restoreExitBinding)
            }
          }
        }

        PanelSeparator {
          visible: ivpn.operational
          foreground: root.foreground
        }

        // --- CONFIGURATION SECTION ---
        Column {
          visible: ivpn.operational
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "CONFIGURATION"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Dropdown {
            id: protocolDropdown
            width: parent.width
            label: "TUNNEL PROTOCOL"
            value: ivpn.protocol
            options: root.protocolOptions
            enabled: !ivpn.actionBusy
            opacity: enabled ? 1.0 : 0.5
            hasCursor: root.cursorActive && root.cursorIndex === 3
            foreground: root.foreground
            background: root.background
            fontFamily: root.fontFamily
            onHovered: function(hovered) { if (hovered && !ivpn.actionBusy) root.setCursor(3) }
            onChanged: function(value) {
              if (value !== ivpn.protocol) ivpn.setProtocol(value)
              Qt.callLater(root.restoreProtocolBinding)
            }
          }

          Dropdown {
            id: antiTrackerDropdown
            width: parent.width
            label: "ANTITRACKER (ADS & TRACKERS)"
            value: ivpn.antiTracker
            options: root.antiTrackerOptions
            enabled: !ivpn.actionBusy
            opacity: enabled ? 1.0 : 0.5
            hasCursor: root.cursorActive && root.cursorIndex === 4
            foreground: root.foreground
            background: root.background
            fontFamily: root.fontFamily
            onHovered: function(hovered) { if (hovered && !ivpn.actionBusy) root.setCursor(4) }
            onChanged: function(value) {
              if (value !== ivpn.antiTracker) ivpn.setAntiTracker(value)
              Qt.callLater(root.restoreAntiTrackerBinding)
            }
          }

          Toggle {
            id: firewallToggle
            width: parent.width
            label: "Kill Switch Firewall"
            description: ivpn.firewallPersistent
              ? "Active (Persistent) · Blocks all non-VPN traffic"
              : "Blocks all internet traffic outside the VPN tunnel"
            checked: ivpn.firewallEnabled
            enabled: !ivpn.actionBusy
            opacity: enabled ? 1.0 : 0.5
            hasCursor: root.cursorActive && root.cursorIndex === 5
            foreground: root.foreground
            fontFamily: root.fontFamily
            onHovered: function(hovered) { if (hovered && !ivpn.actionBusy) root.setCursor(5) }
            onClicked: ivpn.toggleFirewall()
          }

          Toggle {
            id: allowLanToggle
            visible: ivpn.firewallEnabled
            width: parent.width
            label: "Allow LAN Traffic"
            description: "Permit local network printers, SSH, and LAN devices"
            checked: ivpn.firewallAllowLan
            enabled: !ivpn.actionBusy
            opacity: enabled ? 1.0 : 0.5
            hasCursor: root.cursorActive && root.cursorIndex === 6
            foreground: root.foreground
            fontFamily: root.fontFamily
            onHovered: function(hovered) { if (hovered && !ivpn.actionBusy) root.setCursor(6) }
            onClicked: ivpn.toggleAllowLan()
          }
        }

        Text {
          width: parent.width
          text: "↑/↓ move · Enter select · t toggle · f fastest · k firewall · r refresh · Tab switch"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }
      }
    }

    Item {
      id: confirmKeys
      anchors.fill: parent
      visible: root.confirmStartDaemon
      focus: visible
      z: 20
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (daemonConfirm.handleKey(event)) event.accepted = true
      }
    }

    ConfirmDialog {
      id: daemonConfirm
      anchors.fill: parent
      z: 10
      opened: root.confirmStartDaemon
      message: "Enable and start ivpn-service using administrator authentication (Polkit)?"
      cancelText: "Cancel"
      confirmText: "Start"
      background: root.background
      foreground: root.foreground
      scrim: Util.alpha(root.background, 0.78)
      fontFamily: root.fontFamily
      onCanceled: root.closeConfirm()
      onConfirmed: {
        root.closeConfirm()
        ivpn.startDaemon()
      }
    }
  }
}
