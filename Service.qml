import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  property bool pollingPaused: false

  // Connection & daemon state
  property string state: "checking" // checking | connected | paused | connecting | disconnected | logged-out | daemon-down | missing-client | error
  property bool connected: false
  property bool paused: false
  property bool loggedIn: false
  property bool guiInstalled: false
  property string protocol: "wg"
  property string activeProtocol: ""
  property string hostname: ""
  property string exitHostname: ""
  property bool multiHop: false
  property string locationLabel: ""
  property string exitLabel: ""
  property string countryCode: ""
  property string exitCountryCode: ""
  property string localIp: ""
  property string localIpv6: ""
  property string dns: ""
  property string connectedSince: ""
  property string pausedTill: ""
  property bool firewallEnabled: false
  property bool firewallPersistent: false
  property bool firewallAllowLan: false
  property bool splitTunnel: false
  property string antiTracker: "off"
  property string antiTrackerSummary: ""

  // Selected target values (for dropdowns)
  property string selectedLocation: "__fastest__"
  property string selectedExit: "" // "" = single-hop

  // Loaded servers for current protocol
  property var servers: []
  property string _serversProto: ""

  property bool refreshing: false
  property bool actionBusy: false
  property string actionStatus: ""
  property string statusError: ""
  property string actionError: ""

  readonly property bool busy: refreshing || actionBusy
  readonly property bool installed: state !== "missing-client"
  readonly property bool daemonRunning: installed && state !== "daemon-down"
  readonly property bool operational: daemonRunning && loggedIn
  readonly property int refreshIntervalSec: boundedInt(settings ? settings.refreshIntervalSec : 10, 10, 5, 300)

  property string _readStep: ""
  property string _readOut: ""
  property string _readErr: ""
  property bool _ignoreReadExit: false
  property bool _wantDetails: false
  property bool _refreshQueued: false
  property bool _queuedDetails: false

  property string _actionKind: ""
  property string _actionOut: ""
  property string _actionErr: ""
  property bool _ignoreActionExit: false

  function boundedInt(value, fallback, minimum, maximum) {
    var n = parseInt(String(value), 10)
    if (!isFinite(n)) n = fallback
    return Math.max(minimum, Math.min(maximum, n))
  }

  function serverByHost(host) {
    if (!host) return null
    for (var i = 0; i < servers.length; i++) {
      if (servers[i].hostname === host) return servers[i]
    }
    return null
  }

  function activeServerLabel() {
    var s = serverByHost(hostname)
    if (s) return s.label
    if (locationLabel) return locationLabel
    return hostname
  }

  function activeExitLabel() {
    var s = serverByHost(exitHostname)
    if (s) return s.label
    if (exitLabel) return exitLabel
    return exitHostname
  }

  function activeCountryCode() {
    if (multiHop && exitCountryCode) return exitCountryCode
    if (countryCode) return countryCode
    var s = serverByHost(hostname)
    return s ? s.countryCode : ""
  }

  function statusJson() {
    return JSON.stringify({
      state: state,
      connected: connected,
      paused: paused,
      loggedIn: loggedIn,
      protocol: activeProtocol || protocol,
      hostname: hostname,
      location: activeServerLabel(),
      countryCode: activeCountryCode(),
      multiHop: multiHop,
      exitHostname: exitHostname,
      localIp: localIp,
      firewallEnabled: firewallEnabled,
      firewallAllowLan: firewallAllowLan,
      antiTracker: antiTracker,
      busy: busy,
      error: actionError || statusError
    })
  }

  function refresh(details) {
    var wantsDetails = details === true
    if (readProcess.running || actionProcess.running) {
      _refreshQueued = true
      _queuedDetails = _queuedDetails || wantsDetails
      return
    }
    _refreshQueued = false
    _queuedDetails = false
    _wantDetails = wantsDetails
    refreshing = true
    startRead("status")
  }

  function startRead(step) {
    var cmd = Model.command(step, "", { protocol: protocol })
    if (!cmd.length) {
      finishRefresh()
      return
    }
    _readStep = step
    _readOut = ""
    _readErr = ""
    readProcess.command = cmd
    readProcess.running = true
    readWatchdog.restart()
  }

  function applyStatus(exitCode) {
    var r = Model.parseStatus(_readOut, _readErr, exitCode)
    state = r.state
    connected = r.connected
    paused = r.paused
    loggedIn = r.loggedIn
    statusError = r.error || ""
    firewallEnabled = r.firewallEnabled
    firewallPersistent = r.firewallPersistent
    firewallAllowLan = r.firewallAllowLan
    splitTunnel = r.splitTunnel
    antiTrackerSummary = r.antiTrackerSummary

    if (r.connected || r.paused) {
      activeProtocol = r.protocol || protocol
      if (r.protocol) protocol = r.protocol
      hostname = r.hostname
      exitHostname = r.exitHostname
      multiHop = r.multiHop
      locationLabel = r.locationLabel
      exitLabel = r.exitLabel
      countryCode = r.countryCode
      exitCountryCode = r.exitCountryCode
      localIp = r.localIp
      localIpv6 = r.localIpv6
      dns = r.dns
      connectedSince = r.connectedSince
      pausedTill = r.pausedTill
      if (r.hostname) selectedLocation = r.hostname
      selectedExit = r.multiHop ? r.exitHostname : ""
    } else {
      activeProtocol = ""
      hostname = ""
      exitHostname = ""
      multiHop = false
      locationLabel = ""
      exitLabel = ""
      countryCode = ""
      exitCountryCode = ""
      localIp = ""
      localIpv6 = ""
      dns = ""
      connectedSince = ""
      pausedTill = ""
    }

    if (state === "missing-client" || state === "daemon-down") {
      finishRefresh()
      return
    }

    if (_wantDetails) {
      startRead("antitracker-status")
    } else if (servers.length === 0 || _serversProto !== protocol) {
      startRead("servers")
    } else {
      finishRefresh()
    }
  }

  function applyAntiTracker(exitCode) {
    var parsed = Model.parseAntiTracker(_readOut, exitCode)
    if (parsed !== "unknown") antiTracker = parsed
    if (servers.length === 0 || _serversProto !== protocol) {
      startRead("servers")
    } else {
      finishRefresh()
    }
  }

  function applyServers(exitCode) {
    var list = Model.parseServers(_readOut, exitCode)
    if (list.length > 0) {
      servers = list
      _serversProto = protocol
    }
    finishRefresh()
  }

  function readFinished(exitCode) {
    readWatchdog.stop()
    if (_ignoreReadExit) {
      _ignoreReadExit = false
      return
    }
    _readOut = String(readStdout.text || _readOut || "")
    _readErr = String(readStderr.text || _readErr || "")

    if (_readStep === "status") applyStatus(exitCode)
    else if (_readStep === "antitracker-status") applyAntiTracker(exitCode)
    else if (_readStep === "servers") applyServers(exitCode)
    else finishRefresh()
  }

  function finishRefresh() {
    readWatchdog.stop()
    refreshing = false
    _readStep = ""
    _wantDetails = false
    if (_refreshQueued && !actionProcess.running) {
      var d = _queuedDetails
      _refreshQueued = false
      _queuedDetails = false
      Qt.callLater(function() { root.refresh(d) })
    }
  }

  function showActionError(msg) {
    actionError = String(msg || "IVPN action failed")
    actionErrorTimer.restart()
  }

  function actionLabel(kind) {
    if (kind === "connect-fastest") return "Connecting to fastest server…"
    if (kind === "connect-random") return "Connecting to random server…"
    if (kind === "connect-location" || kind === "connect-last") return "Connecting…"
    if (kind === "disconnect") return "Disconnecting…"
    if (kind === "pause") return "Pausing VPN…"
    if (kind === "resume") return "Resuming VPN…"
    if (kind === "firewall" || kind === "firewall-lan") return "Updating firewall…"
    if (kind === "antitracker") return "Updating AntiTracker…"
    if (kind === "login") return "Logging in…"
    if (kind === "start-daemon") return "Starting IVPN service…"
    return "Working…"
  }

  function runAction(kind, value, extra) {
    if (actionProcess.running || actionBusy) return false
    var cmd = Model.command(kind, value, extra || {
      protocol: protocol,
      exitHostname: selectedExit
    })
    if (!cmd.length) {
      showActionError("Invalid IVPN command")
      return false
    }

    if (readProcess.running) {
      _ignoreReadExit = true
      readWatchdog.stop()
      readProcess.running = false
      refreshing = false
    }

    _actionKind = kind
    _actionOut = ""
    _actionErr = ""
    actionError = ""
    actionErrorTimer.stop()
    actionStatus = actionLabel(kind)
    actionBusy = true
    actionProcess.command = cmd
    actionProcess.running = true
    actionWatchdog.restart()
    return true
  }

  function actionFinished(exitCode) {
    actionWatchdog.stop()
    if (_ignoreActionExit) {
      _ignoreActionExit = false
      return
    }
    if (!actionBusy) return

    _actionOut = String(actionStdout.text || _actionOut || "")
    _actionErr = String(actionStderr.text || _actionErr || "")

    var failed = Number(exitCode) !== 0
    actionBusy = false
    actionStatus = ""

    if (failed) {
      showActionError(Model.summarizeError(_actionOut, _actionErr, exitCode))
    }
    refresh(true)
  }

  function connect() {
    if (!operational) return false
    if (selectedLocation && selectedLocation !== "__fastest__" && selectedLocation !== "__random__") {
      return runAction("connect-location", selectedLocation, { protocol: protocol, exitHostname: selectedExit })
    }
    if (selectedLocation === "__random__") {
      return runAction("connect-random", "", { protocol: protocol, exitHostname: selectedExit })
    }
    return runAction("connect-fastest", "", { protocol: protocol, exitHostname: selectedExit })
  }

  function connectFastest() {
    if (!operational) return false
    selectedLocation = "__fastest__"
    return runAction("connect-fastest", "", { protocol: protocol, exitHostname: selectedExit })
  }

  function connectTo(locationValue) {
    if (!operational) return false
    selectedLocation = locationValue
    var entryS = serverByHost(locationValue)
    var exitS = serverByHost(selectedExit)
    if (entryS && exitS && entryS.countryCode && entryS.countryCode === exitS.countryCode) {
      selectedExit = ""
    }
    return runAction("connect-location", locationValue, { protocol: protocol, exitHostname: selectedExit })
  }

  function setExitServer(exitValue) {
    selectedExit = exitValue || ""
    if (operational && connected) {
      return connect()
    }
    return true
  }

  function setProtocol(proto) {
    if (proto !== "wg" && proto !== "ovpn") return false
    if (proto === protocol) return true
    protocol = proto
    if (selectedLocation && selectedLocation !== "__fastest__" && selectedLocation !== "__random__") {
      selectedLocation = proto === "wg"
        ? selectedLocation.replace(/\.gw\.ivpn\.net$/, ".wg.ivpn.net")
        : selectedLocation.replace(/\.wg\.ivpn\.net$/, ".gw.ivpn.net")
    }
    if (selectedExit) {
      selectedExit = proto === "wg"
        ? selectedExit.replace(/\.gw\.ivpn\.net$/, ".wg.ivpn.net")
        : selectedExit.replace(/\.wg\.ivpn\.net$/, ".gw.ivpn.net")
    }
    _serversProto = ""
    if (operational && connected) {
      return connect()
    }
    refresh(true)
    return true
  }

  function disconnect() {
    if (!operational) return false
    return runAction("disconnect", "")
  }

  function toggleVpn() {
    if (!operational) return false
    if (paused) return runAction("resume", "")
    return connected ? disconnect() : connect()
  }

  function pause(minutes) {
    if (!operational || !connected) return false
    return runAction("pause", String(minutes || 15))
  }

  function resume() {
    if (!operational || !paused) return false
    return runAction("resume", "")
  }

  function toggleFirewall() {
    if (!daemonRunning) return false
    return runAction("firewall", firewallEnabled ? "off" : "on")
  }

  function toggleAllowLan() {
    if (!daemonRunning) return false
    return runAction("firewall-lan", firewallAllowLan ? "block" : "allow")
  }

  function setAntiTracker(presetValue) {
    if (!daemonRunning) return false
    antiTracker = presetValue
    return runAction("antitracker", presetValue)
  }

  function login(accountId) {
    var id = String(accountId || "").trim()
    if (!Model.validAccountId(id)) {
      showActionError("Enter a valid IVPN Account ID (e.g. i-XXXX-XXXX-XXXX)")
      return false
    }
    return runAction("login", id)
  }

  function startDaemon() {
    return runAction("start-daemon", "")
  }

  function openGui() {
    if (!guiInstalled) return
    Quickshell.execDetached(["/opt/ivpn/ui/bin/ivpn-ui"])
  }

  Process {
    id: guiCheckProcess
    command: ["test", "-x", "/opt/ivpn/ui/bin/ivpn-ui"]
    onExited: function(exitCode) { root.guiInstalled = (Number(exitCode) === 0) }
  }

  Process {
    id: readProcess
    stdout: StdioCollector { id: readStdout; waitForEnd: true; onStreamFinished: root._readOut = text }
    stderr: StdioCollector { id: readStderr; waitForEnd: true; onStreamFinished: root._readErr = text }
    onExited: function(exitCode) { root.readFinished(exitCode) }
  }

  Process {
    id: actionProcess
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOut = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionErr = text }
    onExited: function(exitCode) { root.actionFinished(exitCode) }
  }

  Timer {
    id: pollTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: !root.pollingPaused
    onTriggered: root.refresh(false)
  }

  Timer {
    id: actionErrorTimer
    interval: 8000
    onTriggered: root.actionError = ""
  }

  Timer {
    id: readWatchdog
    interval: 10000
    onTriggered: {
      root._ignoreReadExit = true
      if (readProcess.running) readProcess.running = false
      root.finishRefresh()
    }
  }

  Timer {
    id: actionWatchdog
    interval: root._actionKind === "start-daemon" ? 120000 : 30000
    onTriggered: {
      root._ignoreActionExit = true
      if (actionProcess.running) actionProcess.running = false
      root.actionBusy = false
      root.actionStatus = ""
      root.showActionError("IVPN action timed out")
      root.refresh(true)
    }
  }

  Component.onCompleted: {
    guiCheckProcess.running = true
    Qt.callLater(function() { root.refresh(true) })
  }
}
