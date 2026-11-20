const test = require("node:test");
const assert = require("node:assert/strict");
const Model = require("../Model.js");

test("parseStatus: live IVPN 3.15.15 connected single-hop output", () => {
  const out = [
    "Account                : Logged in",
    "VPN                    : CONNECTED",
    "    Location           : us-tx.wg.ivpn.net [us-tx4.wg.ivpn.net], Dallas, TX (US), United States",
    "    Protocol           : WireGuard",
    "    Local IP           : 172.27.193.91",
    "    Connected          : 2026-11-20 16:44:13 -0600 CST",
    "AntiTracker            : Enabled (block list: 'Basic')",
    "Split Tunnel           : Disabled",
    "Firewall               : Enabled",
    "    Allow LAN          : false",
    "    Allow IVPN servers : true"
  ].join("\n");

  const r = Model.parseStatus(out, "", 0);
  assert.equal(r.state, "connected");
  assert.equal(r.connected, true);
  assert.equal(r.loggedIn, true);
  assert.equal(r.protocol, "wg");
  assert.equal(r.hostname, "us-tx.wg.ivpn.net");
  assert.equal(r.countryCode, "US");
  assert.equal(r.locationLabel, "Dallas, TX (US), United States");
  assert.equal(r.localIp, "172.27.193.91");
  assert.equal(r.firewallEnabled, true);
  assert.equal(r.firewallAllowLan, false);
  assert.equal(r.multiHop, false);
});

test("parseStatus: multi-hop connected output", () => {
  const out = [
    "Account : Logged in",
    "VPN : CONNECTED",
    "    Entry : Zurich (CH), Switzerland (ch.wg.ivpn.net)",
    "    Exit : Stockholm (SE), Sweden (se.wg.ivpn.net)",
    "    Protocol : WireGuard",
    "    Local IP : 172.24.10.5",
    "Firewall : Enabled (Persistent)",
    "    Allow LAN : true"
  ].join("\n");

  const r = Model.parseStatus(out, "", 0);
  assert.equal(r.state, "connected");
  assert.equal(r.multiHop, true);
  assert.equal(r.hostname, "ch.wg.ivpn.net");
  assert.equal(r.countryCode, "CH");
  assert.equal(r.exitHostname, "se.wg.ivpn.net");
  assert.equal(r.exitCountryCode, "SE");
  assert.equal(r.firewallPersistent, true);
  assert.equal(r.firewallAllowLan, true);
});

test("parseStatus: logged-out, daemon-down, and missing-client states", () => {
  const loggedOut = Model.parseStatus(
    "Account : Not logged in\nVPN : DISCONNECTED\nError: not logged in",
    "",
    1
  );
  assert.equal(loggedOut.state, "logged-out");
  assert.equal(loggedOut.loggedIn, false);

  const daemonDown = Model.parseStatus(
    "",
    "Error: failed to connect to IVPN daemon: connection refused",
    1
  );
  assert.equal(daemonDown.state, "daemon-down");

  const missing = Model.parseStatus("", "env: 'ivpn': No such file or directory", 127);
  assert.equal(missing.state, "missing-client");
});

test("parseServers: parses and sorts IVPN server table", () => {
  const table = [
    "  PROTOCOL|              LOCATION|                      CITY|         COUNTRY|             ISP| IPv? tunnel|",
    " WireGuard|        ch.wg.ivpn.net|               Zurich (CH)|     Switzerland| <multiple ISPs>|   IPv4/IPv6|",
    " WireGuard|        at.wg.ivpn.net|               Vienna (AT)|         Austria|      Datapacket|   IPv4/IPv6|"
  ].join("\n");

  const servers = Model.parseServers(table, 0);
  assert.equal(servers.length, 2);
  assert.equal(servers[0].hostname, "at.wg.ivpn.net");
  assert.equal(servers[0].label, "Austria · Vienna (AT)");
  assert.equal(servers[1].hostname, "ch.wg.ivpn.net");
  assert.equal(servers[1].countryCode, "CH");
  assert.equal(servers[1].description, "ch.wg.ivpn.net · Multiple ISPs · IPv4/IPv6");
});

test("parseAntiTracker: maps presets accurately", () => {
  assert.equal(Model.parseAntiTracker("Default config : AntiTracker Disabled", 0), "off");
  assert.equal(Model.parseAntiTracker("Default config : AntiTracker Enabled (block list: 'Basic')", 0), "on:Basic");
  assert.equal(Model.parseAntiTracker("Default config : AntiTracker Enabled (block list: 'Oisdbig')", 0), "on:Oisdbig");
  assert.equal(Model.parseAntiTracker("Default config : AntiTracker Hardcore (block list: 'Hageziproplus')", 0), "hardcore:Hageziproplus");
});

test("command: builds strict argument arrays and rejects unsafe input", () => {
  assert.deepEqual(
    Model.command("connect-location", "ch.wg.ivpn.net", { protocol: "wg", exitHostname: "se.wg.ivpn.net" }),
    ["env", "LC_ALL=C", "LANG=C", "NO_COLOR=1", "TERM=dumb", "ivpn", "connect", "-l", "ch.wg.ivpn.net", "-p", "wg", "-exit_svr", "se.wg.ivpn.net"]
  );
  assert.deepEqual(Model.command("connect-location", "bad;rm -rf /", { protocol: "wg" }), []);
  assert.deepEqual(Model.command("login", "bad id; whoami"), []);
  assert.deepEqual(
    Model.command("login", "i-1234-5678-9012"),
    ["env", "LC_ALL=C", "LANG=C", "NO_COLOR=1", "TERM=dumb", "ivpn", "login", "i-1234-5678-9012"]
  );
  assert.deepEqual(
    Model.command("start-daemon"),
    ["pkexec", "systemctl", "enable", "--now", "ivpn-service"]
  );
});
