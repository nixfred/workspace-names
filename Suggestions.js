// Local window metadata only. Suggestions are display fallbacks; never written
// over manual names or attached to workspace IDs that Plonk can renumber.
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

function candidate(client) {
  var app = clean(client.class || client.initialClass).toLowerCase();
  var title = clean(client.title || client.initialTitle);
  if (/cliamp|spotify|music|rhythmbox/.test(app + " " + title.toLowerCase()))
    return { name: "Music", score: 3 };
  title = title.replace(/\s+[-—–|]\s+(?:Brave|Google Chrome|Chromium|Mozilla Firefox|Visual Studio Code|VSCodium|Cursor|foot|Alacritty|kitty|Ghostty)$/i, "");
  title = title.replace(/\s+[-—–|]\s+(?:Brave|Google Chrome|Chromium|Mozilla Firefox)$/i, "");
  if (title && !/^(?:pi|claude|codex|bash|zsh|fish|foot|alacritty|kitty|ghostty|new tab|terminal)$/i.test(title)
      && !/^[^\s@]+@[^\s:]+(?::.*)?$/.test(title)) {
    return { name: shorten(title), score: 4 };
  }
  var combined = app + " " + title.toLowerCase();
  var categories = [
    [/\bpi\b/, "Pi"], [/claude/, "Claude"], [/codex/, "Codex"],
    [/brave|firefox|chromium|chrome/, "Browsing"],
    [/code|cursor|zed|neovim|nvim/, "Code"],
    [/thunar|nautilus|dolphin/, "Files"], [/slack|discord|signal|telegram/, "Chat"],
    [/foot|alacritty|kitty|ghostty|terminal/, "Terminal"]
  ];
  for (var i = 0; i < categories.length; i++) {
    if (categories[i][0].test(combined)) return { name: categories[i][1], score: 1 };
  }
  return { name: shorten(clean(client.class || client.initialClass)), score: 0 };
}

function fromClients(clients) {
  var best = {}, result = {};
  for (var i = 0; i < clients.length; i++) {
    var client = clients[i] || {};
    var id = client.workspace ? Number(client.workspace.id) : 0;
    if (id < 1 || !isFinite(id) || client.mapped === false) continue;
    var entry = candidate(client);
    if (!entry.name) continue;
    var rank = Number(client.focusHistoryID);
    entry.rank = isFinite(rank) && rank >= 0 ? rank : 999999;
    var previous = best[id];
    if (!previous || entry.score > previous.score ||
        (entry.score === previous.score && entry.rank < previous.rank)) best[id] = entry;
  }
  for (var key in best) result[key] = best[key].name;
  return result;
}

function label(manual, suggestions, id) {
  return clean((manual || {})[String(id)]) || (suggestions || {})[String(id)] || "";
}
