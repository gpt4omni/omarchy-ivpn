/* Pure, QML-compatible IVPN CLI parsing and command planning. */

var PROTOCOLS = ["wg", "ovpn"]

var ANTITRACKER_PRESETS = [
  { value: "off", label: "Off", args: ["-off"] },
  { value: "on:Basic", label: "Standard · Basic", args: ["-on", "Basic"] },
  { value: "on:Oisdbig", label: "Standard · OISD Big", args: ["-on", "Oisdbig"] },
  { value: "on:Hagezipro", label: "Standard · HaGeZi Pro", args: ["-on", "Hagezipro"] },
  { value: "hardcore:Basic", label: "Hardcore · Basic", args: ["-on_hardcore", "Basic"] },
  { value: "hardcore:Hageziproplus", label: "Hardcore · HaGeZi Pro++", args: ["-on_hardcore", "Hageziproplus"] }
]

function str(v) {
  return String(v === undefined || v === null ? "" : v)
}

function clean(v) {
  return str(v).replace(/\x1b\[[0-?]*[ -\/]*[@-~]/g, "").trim()
}

function compact(v) {
  return clean(v).replace(/\s+/g, " ")
}

function lower(v) {
  return compact(v).toLowerCase()
}

function escapeRegExp(v) {
  return str(v).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function fieldValue(raw, names) {
  var lines = clean(raw).split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    for (var j = 0; j < names.length; j++) {
      var re = new RegExp("^\\s*" + escapeRegExp(names[j]) + "\\s*:\\s*(.*?)\\s*$", "i")
      var m = lines[i].match(re)
      if (m) return m[1].trim()
    }
  }
  return ""
}

function boolVal(v) {
  var s = lower(v)
  return s === "true" || s === "yes" || s === "enabled" || s === "on" || s.indexOf("enabled") === 0
}

function extractHost(text) {
  var m = str(text).match(/([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:wg|gw)\.ivpn\.net)/i)
  return m ? m[1].toLowerCase() : ""
}

function extractCountryCode(text) {
  var m = str(text).match(/\(([A-Z]{2})\)/)
  return m ? m[1] : ""
}

function normalizeProtocol(v) {
  var s = lower(v)
  if (s.indexOf("wireguard") !== -1 || s === "wg") return "wg"
  if (s.indexOf("openvpn") !== -1 || s === "ovpn") return "ovpn"
  return ""
}

function cleanLocationLabel(text) {
  var s = compact(text)
  if (!s) return ""
  var stripped = s
    .replace(/^[a-z0-9.-]+\.(?:wg|gw)\.ivpn\.net(?:\s*\[[^\]]+\])?\s*,\s*/i, "")
    .replace(/\s*\([a-z0-9.-]+\.(?:wg|gw)\.ivpn\.net[^)]*\)\s*/gi, "")
    .trim()
  return stripped || s
}

function parseStatus(stdout, stderr, exitCode) {
  var out = clean(stdout)
  var err = clean(stderr)
  var all = lower(out + "\n" + err)

  var res = {
    state: "unknown",
    connected: false,
    paused: false,
    loggedIn: false,
    vpnRaw: "",
    protocol: "",
    hostname: "",
    exitHostname: "",
    multiHop: false,
    locationLabel: "",
    city: "",
    country: "",
    countryCode: "",
    exitLabel: "",
    exitCountryCode: "",
    localIp: "",
    localIpv6: "",
    dns: "",
    connectedSince: "",
    pausedTill: "",
    firewallEnabled: false,
    firewallPersistent: false,
    firewallAllowLan: false,
    antiTrackerSummary: "",
    splitTunnel: false,
    error: ""
  }

  if (Number(exitCode) === 127 || /ivpn:.*not found|command not found|no such file or directory.*['"]?ivpn['"]?/.test(all)) {
    res.state = "missing-client"
    res.error = "ivpn CLI is not installed"
    return res
  }

  if (/failed to connect to.*daemon|cannot connect to.*daemon|connection refused|ivpn-service.*not running|daemon.*not running|dial unix.*ivpn/.test(all)) {
    res.state = "daemon-down"
    res.error = "IVPN daemon (ivpn-service) is not running"
    return res
  }

  var accountVal = fieldValue(out, ["Account"])
  var fwVal = fieldValue(out, ["Firewall"])
  res.firewallEnabled = /^enabled/i.test(fwVal)
  res.firewallPersistent = /persistent/i.test(fwVal) || boolVal(fieldValue(out, ["Persistent"]))
  res.firewallAllowLan = boolVal(fieldValue(out, ["Allow LAN"]))
  res.splitTunnel = boolVal(fieldValue(out, ["Split Tunnel"]))

  if (/not logged in/i.test(accountVal) || /error:\s*not logged in/i.test(all)) {
    res.state = "logged-out"
    res.loggedIn = false
    res.error = ""
    return res
  }

  res.loggedIn = true

  var vpnVal = fieldValue(out, ["VPN"])
  res.vpnRaw = vpnVal
  var vpnLow = lower(vpnVal)

  res.protocol = normalizeProtocol(fieldValue(out, ["Protocol"]))
  res.localIp = fieldValue(out, ["Local IP"])
  res.localIpv6 = fieldValue(out, ["Local IPv6"])
  res.dns = fieldValue(out, ["DNS"])
  res.connectedSince = fieldValue(out, ["Connected"])
  res.pausedTill = fieldValue(out, ["Paused till", "Paused until"])
  res.antiTrackerSummary = fieldValue(out, ["AntiTracker"])

  var lines = out.split(/\r?\n/)
  var entryLine = fieldValue(out, ["Entry", "Location", "Server"])
  var exitLine = fieldValue(out, ["Exit"])

  if (entryLine === "" && vpnVal.indexOf("(") !== -1) {
    entryLine = vpnVal.replace(/^(?:CONNECTED|PAUSED|CONNECTING|RECONNECTING)\s*/i, "").trim()
  }
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^\s*VPN\s*:/i.test(line)) {
      for (var k = i + 1; k < lines.length; k++) {
        if (!/^\s+/.test(lines[k])) break
        var trimmed = lines[k].trim()
        if (entryLine === "" && /\.(?:wg|gw)\.ivpn\.net/i.test(trimmed) && !/^Exit\b/i.test(trimmed)) {
          entryLine = trimmed.replace(/^[^:]+:\s*/, "")
        } else if (exitLine === "" && /^Exit\b/i.test(trimmed)) {
          exitLine = trimmed.replace(/^Exit\s*:\s*/i, "")
        }
      }
      break
    }
  }

  if (entryLine.indexOf("->") !== -1) {
    var hopParts = entryLine.split("->")
    entryLine = hopParts[0].trim()
    if (exitLine === "") exitLine = hopParts[1].trim()
  }

  res.hostname = extractHost(entryLine) || extractHost(out)
  res.countryCode = extractCountryCode(entryLine)
  if (!res.countryCode && res.hostname) {
    var hostCc = res.hostname.match(/^([a-z]{2})(?:[-.]|$)/i)
    if (hostCc) res.countryCode = hostCc[1].toUpperCase()
  }
  res.locationLabel = cleanLocationLabel(entryLine)

  if (exitLine !== "") {
    res.multiHop = true
    res.exitHostname = extractHost(exitLine)
    res.exitCountryCode = extractCountryCode(exitLine)
    if (!res.exitCountryCode && res.exitHostname) {
      var exitCc = res.exitHostname.match(/^([a-z]{2})(?:[-.]|$)/i)
      if (exitCc) res.exitCountryCode = exitCc[1].toUpperCase()
    }
    res.exitLabel = cleanLocationLabel(exitLine)
  }

  if (/^connected\b/.test(vpnLow)) {
    res.state = "connected"
    res.connected = true
  } else if (/^paused\b/.test(vpnLow)) {
    res.state = "paused"
    res.connected = true
    res.paused = true
  } else if (/^(?:connecting|reconnecting|disconnecting|initializing)\b/.test(vpnLow)) {
    res.state = "connecting"
    res.connected = false
  } else if (/^disconnected\b/.test(vpnLow)) {
    res.state = "disconnected"
    res.connected = false
  } else if (Number(exitCode) !== 0) {
    res.state = "error"
    res.error = err || out || ("ivpn status failed (exit " + exitCode + ")")
  } else {
    res.state = "disconnected"
    res.connected = false
  }

  return res
}

function parseServers(stdout, exitCode) {
  if (Number(exitCode) !== 0) return []
  var lines = clean(stdout).split(/\r?\n/)
  var items = []
  var seen = {}

  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("|") === -1) continue
    var cols = line.split("|")
    if (cols.length < 4) continue

    var proto = compact(cols[0])
    var host = compact(cols[1]).toLowerCase()
    var cityRaw = compact(cols[2])
    var country = compact(cols[3])
    var isp = cols.length > 4 ? compact(cols[4]) : ""
    var ipv = cols.length > 5 ? compact(cols[5]) : ""

    if (!host || /^location$/i.test(host) || /^protocol$/i.test(proto)) continue
    if (!/^[a-z0-9.-]+$/.test(host)) continue
    if (seen[host]) continue
    seen[host] = true

    var cc = extractCountryCode(cityRaw)
    if (!cc) {
      var hm = host.match(/^([a-z]{2})(?:[-.]|$)/)
      if (hm) cc = hm[1].toUpperCase()
    }
    var cityClean = cityRaw.replace(/\s*\([A-Z]{2}\)\s*$/, "").trim() || cityRaw
    var label = country + " · " + cityClean + (cc ? " (" + cc + ")" : "")
    var descParts = [host]
    if (isp && isp !== "<multiple ISPs>") descParts.push(isp)
    else if (isp === "<multiple ISPs>") descParts.push("Multiple ISPs")
    if (ipv) descParts.push(ipv)

    items.push({
      value: host,
      hostname: host,
      label: label,
      description: descParts.join(" · "),
      country: country,
      countryCode: cc,
      city: cityClean,
      isp: isp,
      protocol: normalizeProtocol(proto)
    })
  }

  items.sort(function(a, b) {
    if (a.country !== b.country) return a.country.localeCompare(b.country)
    return a.city.localeCompare(b.city)
  })
  return items
}

function parseAntiTracker(stdout, exitCode) {
  var out = lower(stdout)
  if (Number(exitCode) !== 0 || !out) return "unknown"
  if (/disabled|off/.test(out) && !/enabled|hardcore/.test(out)) return "off"

  var hardcore = /hardcore/.test(out)
  var prefix = hardcore ? "hardcore:" : "on:"

  if (/hageziproplus|hagezi pro\+\+/.test(out)) return prefix + "Hageziproplus"
  if (/hagezipro|hagezi pro/.test(out)) return prefix + "Hagezipro"
  if (/oisdbig|oisd/.test(out)) return prefix + "Oisdbig"
  if (/basic/.test(out)) return prefix + "Basic"

  return hardcore ? "hardcore:Basic" : "on:Basic"
}

function ivpnBase() {
  return ["env", "LC_ALL=C", "LANG=C", "NO_COLOR=1", "TERM=dumb", "ivpn"]
}

function validHost(h) {
  return typeof h === "string" && /^[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:wg|gw)\.ivpn\.net$/i.test(h) && h.length < 128
}

function validAccountId(id) {
  return typeof id === "string" && /^[A-Za-z0-9-]{6,64}$/.test(id.trim())
}

function command(kind, value, extra) {
  extra = extra || {}
  var proto = PROTOCOLS.indexOf(extra.protocol) !== -1 ? extra.protocol : "wg"

  if (kind === "status") return ivpnBase().concat(["status"])
  if (kind === "antitracker-status") return ivpnBase().concat(["antitracker"])
  if (kind === "servers") return ivpnBase().concat(["servers", "-p", proto])
  if (kind === "disconnect") return ivpnBase().concat(["disconnect"])
  if (kind === "resume") return ivpnBase().concat(["connection", "-resume"])

  if (kind === "pause") {
    var mins = parseInt(String(value || "15"), 10)
    if (!isFinite(mins) || mins < 1 || mins > 1440) mins = 15
    return ivpnBase().concat(["connection", "-pause", String(mins)])
  }

  if (kind === "connect-fastest") {
    var argsF = ["connect", "-f", "-p", proto]
    if (validHost(extra.exitHostname)) argsF = argsF.concat(["-exit_svr", extra.exitHostname])
    return ivpnBase().concat(argsF)
  }

  if (kind === "connect-random") {
    var argsR = ["connect", "-any", "-p", proto]
    if (validHost(extra.exitHostname)) argsR = argsR.concat(["-exit_svr", extra.exitHostname])
    return ivpnBase().concat(argsR)
  }

  if (kind === "connect-last") {
    return ivpnBase().concat(["connect", "-last"])
  }

  if (kind === "connect-location") {
    if (value === "__fastest__") return command("connect-fastest", "", extra)
    if (value === "__random__") return command("connect-random", "", extra)
    if (!validHost(value)) return []
    var argsL = ["connect", "-l", value, "-p", proto]
    if (validHost(extra.exitHostname) && extra.exitHostname !== value) {
      argsL = argsL.concat(["-exit_svr", extra.exitHostname])
    }
    return ivpnBase().concat(argsL)
  }

  if (kind === "firewall") {
    return ivpnBase().concat(["firewall", value === "on" ? "-on" : "-off"])
  }

  if (kind === "firewall-lan") {
    return ivpnBase().concat(["firewall", value === "allow" ? "-lan_allow" : "-lan_block"])
  }

  if (kind === "antitracker") {
    for (var i = 0; i < ANTITRACKER_PRESETS.length; i++) {
      if (ANTITRACKER_PRESETS[i].value === value) {
        return ivpnBase().concat(["antitracker"]).concat(ANTITRACKER_PRESETS[i].args)
      }
    }
    return []
  }

  if (kind === "login") {
    var id = str(value).trim()
    if (!validAccountId(id)) return []
    return ivpnBase().concat(["login", id])
  }

  if (kind === "start-daemon") {
    return ["pkexec", "systemctl", "enable", "--now", "ivpn-service"]
  }

  if (kind === "open-gui") {
    return ["/opt/ivpn/ui/bin/ivpn-ui"]
  }

  return []
}

function summarizeError(stdout, stderr, exitCode) {
  var err = clean(stderr)
  var out = clean(stdout)
  var lines = (err + "\n" + out).split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var l = lines[i].trim()
    if (/^error\s*:/i.test(l)) return l.replace(/^error\s*:\s*/i, "")
  }
  if (err) return err.split(/\r?\n/)[0].slice(0, 140)
  if (out) return out.split(/\r?\n/)[0].slice(0, 140)
  return "IVPN command failed (exit " + Number(exitCode) + ")"
}

if (typeof module !== "undefined") {
  module.exports = {
    PROTOCOLS: PROTOCOLS,
    ANTITRACKER_PRESETS: ANTITRACKER_PRESETS,
    parseStatus: parseStatus,
    parseServers: parseServers,
    parseAntiTracker: parseAntiTracker,
    validHost: validHost,
    validAccountId: validAccountId,
    command: command,
    summarizeError: summarizeError
  }
}
