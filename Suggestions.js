// Local window metadata only. A suggestion is the name of the APP a workspace
// is running — "Brave", "Kitty", "Hermes" — never its window title. Titles
// change with every tab and every prompt; the app is what you mean when you
// say "the browser workspace". Suggestions are display fallbacks and the seed
// for automatic names; they are never written over a name you typed and never
// attached to workspace IDs that Plonk can renumber.
function clean(value) {
  return String(value || "").replace(/[\x00-\x1f\x7f]/g, " ")
    .replace(/^[\s\u2800-\u28ff✳✻✽✶✢✦●○▶▷⏵⏸]+/, "")
    .replace(/\s+/g, " ").trim();
}

function shorten(value) {
  if (value.length <= 36) return value;
  var part = value.slice(0, 35);
  var space = part.lastIndexOf(" ");
  return (space > 20 ? part.slice(0, space) : part) + "…";
}

// Names for classes whose desktop entry says something longer or stranger
// than what anyone calls the app.
var KNOWN = {
  "brave-browser": "Brave", "google-chrome": "Chrome", "chromium": "Chromium",
  "firefox": "Firefox", "code": "VS Code", "vscodium": "VSCodium",
  "org.gnome.nautilus": "Files", "thunar": "Files", "org.kde.dolphin": "Files"
};

// A readable name from a window class alone: "org.gnome.Nautilus" -> "Nautilus",
// "brave-browser" -> "Brave" (via KNOWN), "foot" -> "Foot", "kitty" -> "Kitty".
function prettyClass(cls) {
  var raw = clean(cls);
  if (!raw) return "";
  var known = KNOWN[raw.toLowerCase()];
  if (known) return known;
  var last = raw.split(".").pop();
  last = last.replace(/[-_](?:browser|bin|desktop|app)$/i, "");
  var words = last.split(/[-_]+/).filter(function (w) { return w !== ""; });
  return words.map(function (w) {
    return w === w.toLowerCase() ? w.charAt(0).toUpperCase() + w.slice(1) : w;
  }).join(" ");
}

// The app's name. `resolve(class)` is the shell's desktop-entry lookup when
// the caller has one (the entry's Name is what the app calls itself); the
// class-derived name is the fallback and the tests' only path. A desktop
// Name that is all lowercase ("kitty") is capitalised the same way.
function appName(client, resolve) {
  var cls = clean(client.class || client.initialClass);
  if (!cls) return "";
  var known = KNOWN[cls.toLowerCase()];
  if (known) return known;
  var resolved = "";
  if (typeof resolve === "function") {
    try { resolved = clean(resolve(cls)); } catch (error) { resolved = ""; }
  }
  if (resolved) {
    if (resolved === resolved.toLowerCase()) resolved = resolved.charAt(0).toUpperCase() + resolved.slice(1);
    return shorten(resolved);
  }
  return shorten(prettyClass(cls));
}

// One suggestion per workspace: the app of its most recently focused window.
function fromClients(clients, resolve) {
  var best = {}, result = {};
  for (var i = 0; i < clients.length; i++) {
    var client = clients[i] || {};
    var id = client.workspace ? Number(client.workspace.id) : 0;
    if (id < 1 || !isFinite(id) || client.mapped === false) continue;
    var name = appName(client, resolve);
    if (!name) continue;
    var rank = Number(client.focusHistoryID);
    rank = isFinite(rank) && rank >= 0 ? rank : 999999;
    var previous = best[id];
    if (!previous || rank < previous.rank) best[id] = { name: name, rank: rank };
  }
  for (var key in best) result[key] = best[key].name;
  return result;
}

function label(manual, suggestions, id) {
  return clean((manual || {})[String(id)]) || (suggestions || {})[String(id)] || "";
}
