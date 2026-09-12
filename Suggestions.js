// Local window metadata only. A suggestion says what a workspace is DOING, not
// just which app it holds:
//
//   a terminal   "Claude · windows.on.omarchy · Check progress"
//                the program in the foreground, the project it runs in, and
//                the task its title names (bin/workspace-clients supplies the
//                program and directory as `client.activity`)
//   a browser    "Brave · X · Mark Cuban", "Brave · YouTube · Some talk"
//   anything     "Hermes", "Remote Desktop · Windows VM - Omarchy"
//
// Suggestions are recomputed as windows and titles change, so an automatic name
// follows the work. They are display fallbacks and the seed for automatic
// names; they are never written over a name you typed and never attached to
// workspace IDs that Plonk can renumber.
var MAX_LENGTH = 60;
var SEPARATOR = " · ";

// Control characters out, and the status glyphs agents animate in front of a
// title (Claude's ✳, braille spinners, ◐◑◒◓) so a spinning title is one name.
function clean(value) {
  return String(value || "").replace(/[\x00-\x1f\x7f]/g, " ")
    .replace(/^[\s⠀-⣿✳✻✽✶✢✦●○◐◑◒◓◔◕▶▷⏵⏸⏳⌛·•]+/, "")
    .replace(/\s+/g, " ").trim();
}

function shorten(value, max) {
  var limit = max || MAX_LENGTH;
  if (value.length <= limit) return value;
  var part = value.slice(0, limit - 1);
  var space = part.lastIndexOf(" ");
  return (space > limit * 0.6 ? part.slice(0, space) : part).replace(/[\s·,:;-]+$/, "") + "…";
}

// Parts joined with a middle dot, empty and repeated parts dropped.
function join(parts) {
  var out = [], seen = {};
  for (var i = 0; i < parts.length; i++) {
    var part = clean(parts[i]);
    var key = part.toLowerCase();
    if (!part || seen[key]) continue;
    seen[key] = true;
    out.push(part);
  }
  return shorten(out.join(SEPARATOR));
}

// Names for classes whose desktop entry says something longer or stranger
// than what anyone calls the app.
var KNOWN = {
  "brave-browser": "Brave", "google-chrome": "Chrome", "chromium": "Chromium",
  "firefox": "Firefox", "code": "VS Code", "vscodium": "VSCodium",
  "org.gnome.nautilus": "Files", "thunar": "Files", "org.kde.dolphin": "Files",
  "xfreerdp": "Remote Desktop", "wlfreerdp": "Remote Desktop", "sdl-freerdp": "Remote Desktop"
};

var TERMINALS = {
  "foot": true, "footclient": true, "kitty": true, "alacritty": true,
  "com.mitchellh.ghostty": true, "ghostty": true, "org.wezfurlong.wezterm": true,
  "org.kde.konsole": true, "org.gnome.console": true, "org.gnome.ptyxis": true,
  "xterm": true, "st": true
};

var BROWSERS = {
  "brave-browser": true, "google-chrome": true, "chromium": true, "firefox": true,
  "zen": true, "librewolf": true, "vivaldi-stable": true, "microsoft-edge": true
};

// Foreground programs by what people call them. Anything else shows as its
// own command name, which is usually right ("cmatrix", "ncdu").
var TOOLS = {
  "claude": "Claude", "codex": "Codex", "pi": "Pi", "gemini": "Gemini",
  "opencode": "OpenCode", "aider": "Aider", "grok": "Grok", "crush": "Crush",
  "nvim": "Neovim", "vim": "Vim", "vi": "Vim", "hx": "Helix", "helix": "Helix",
  "nano": "Nano", "emacs": "Emacs", "btop": "btop", "htop": "htop", "top": "top",
  "lazygit": "Lazygit", "lazydocker": "Lazydocker", "yazi": "Yazi", "ranger": "Ranger",
  "herdr": "Herdr", "ssh": "SSH", "mosh": "SSH", "tmux": "tmux", "zellij": "Zellij",
  "man": "man", "less": "less", "python": "Python", "python3": "Python",
  "ipython": "Python", "node": "Node", "bun": "Bun", "cargo": "Cargo",
  "make": "make", "git": "Git", "docker": "Docker", "mpv": "mpv",
  "cliamp": "cliamp", "spotify_player": "Spotify", "impala": "Wi-Fi", "bluetui": "Bluetooth",
  "wiremix": "Audio", "journalctl": "Logs", "watch": "watch", "sudo": "sudo"
};

// Titles a terminal shows when it has nothing to say.
var GENERIC_TITLES = {
  "bash": true, "zsh": true, "fish": true, "sh": true, "terminal": true, "foot": true,
  "kitty": true, "alacritty": true, "ghostty": true, "claude code": true, "claude": true,
  "codex": true, "~": true, "pi": true
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
    return shorten(resolved, 36);
  }
  return shorten(prettyClass(cls), 36);
}

function escapeRegExp(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function basename(path) {
  var parts = String(path || "").replace(/\/+$/, "").split("/");
  return parts[parts.length - 1] || "";
}

// The project a terminal is in: the directory's name, unless it is home or
// the root, which say nothing.
function projectOf(activity) {
  var cwd = String(activity.cwd || "").replace(/\/+$/, "");
  if (!cwd || cwd === "/" || cwd === "/root") return "";
  if (activity.home && cwd === String(activity.home).replace(/\/+$/, "")) return "";
  return basename(cwd);
}

function terminalTask(title, activity, tool, project) {
  var command = String(activity.command || "").toLowerCase();
  var t = clean(title);
  // "Add a launcher | pi": an agent signing its own title.
  var signed = t.match(/^(.*\S)\s+[|•]\s+(\S+)$/);
  if (signed && [command, tool.toLowerCase(), "pi", "claude", "codex"].indexOf(signed[2].toLowerCase()) !== -1) t = signed[1];
  // "gus: workspaces": the host, then what the program called its session.
  if (activity.host && t.indexOf(activity.host + ": ") === 0) t = t.slice(activity.host.length + 2);
  var lower = t.toLowerCase();
  if (!t || GENERIC_TITLES[lower] || lower === command || lower === tool.toLowerCase()) return "";
  if (/^[^\s@]+@[^\s:]+(:.*)?$/.test(t)) return "";   // pi@gus:~/Projects
  if (/^[~/]/.test(t)) return "";                        // a bare path
  if (project && lower === project.toLowerCase()) return "";
  return t;
}

function terminalName(client) {
  var activity = client.activity || {};
  var command = clean(activity.command);
  var tool = command ? (TOOLS[command.toLowerCase()] || command) : "";
  var project = projectOf(activity);
  return join([tool || "Terminal", project, terminalTask(client.title, activity, tool, project)]);
}

function browserName(app, title) {
  var t = clean(title).replace(/^\(\d+\+?\)\s*/, "");
  t = t.replace(/\s+[-—–]\s+(Brave|Google Chrome|Chromium|Mozilla Firefox|Firefox|Zen Browser|Zen|LibreWolf|Vivaldi|Microsoft\s?Edge)$/i, "");
  if (!t || /^(new tab|untitled|about:blank|start page)$/i.test(t)) return app;
  var m;
  if ((m = t.match(/^(.+?) on X: /))) return join([app, "X", m[1]]);
  if ((m = t.match(/^(.+?) \/ X$/))) return join([app, "X", m[1]]);
  if ((m = t.match(/^(.+?) - YouTube$/))) return join([app, "YouTube", m[1]]);
  if ((m = t.match(/^GitHub - ([^\s:]+)/))) return join([app, "GitHub", m[1]]);
  if ((m = t.match(/ · ([\w.-]+\/[\w.-]+)(?: · .*)? · GitHub$/))) return join([app, "GitHub", m[1]]);
  if (/(?:^| - )Gmail$/.test(t) || / - Gmail$/.test(t)) return join([app, "Gmail"]);
  return join([app, t]);
}

function otherName(app, title) {
  var t = clean(title);
  if (app) t = t.replace(new RegExp("\\s+[-—–|]\\s+" + escapeRegExp(app) + "$", "i"), "");
  if (!t || !app || t.toLowerCase() === app.toLowerCase()) return app;
  return join([app, t]);
}

// What one window is doing, in words.
function describe(client, resolve) {
  var app = appName(client, resolve);
  if (!app) return "";
  var cls = clean(client.class || client.initialClass).toLowerCase();
  if (TERMINALS[cls]) return terminalName(client);
  if (BROWSERS[cls]) return browserName(app, client.title);
  return otherName(app, client.title);
}

// One suggestion per workspace: what its most recently focused window is doing.
function fromClients(clients, resolve) {
  var best = {}, result = {};
  for (var i = 0; i < clients.length; i++) {
    var client = clients[i] || {};
    var id = client.workspace ? Number(client.workspace.id) : 0;
    if (id < 1 || !isFinite(id) || client.mapped === false) continue;
    var name = describe(client, resolve);
    if (!name) continue;
    var rank = Number(client.focusHistoryID);
    rank = isFinite(rank) && rank >= 0 ? rank : 999999;
    var previous = best[id];
    if (!previous || rank < previous.rank) best[id] = { name: name, rank: rank };
  }
  for (var key in best) result[key] = best[key].name;
  return result;
}

// What a workspace is called right now. A name you typed wins. A name that
// was written automatically is only the last suggestion that reached the file,
// so the live suggestion is shown in its place — the popup and the bar follow
// what the workspace is doing without waiting for the write.
function label(manual, suggestions, id) {
  var key = String(id);
  var names = manual || {};
  var saved = clean(names[key]);
  var suggested = (suggestions || {})[key] || "";
  var auto = Array.isArray(names._auto) && names._auto.map(String).indexOf(key) !== -1;
  if (saved && auto && suggested) return suggested;
  return saved || suggested || "";
}
