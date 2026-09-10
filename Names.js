// What the names document means — in one place, for every reader.
//
// The same file is read by four things: this plugin's QML, bin/workspace-name,
// bin/workspace-cycle, and Plonk. The shell-side readers all agree, because
// they share one jq predicate: a slot is a key like "5", and a name is a
// non-blank STRING. The QML side did not — it took whatever sat under the key
// and ran String() over it, so `{"2": 42}` put a workspace named "42" in the
// bar that Plonk would never carry on a move, never reserve a slot for, and
// workspace-cycle would never stop on. A name you can see but nothing else
// honours is worse than no name.
//
// The rules, once:
//   slot   — a key matching ^[1-9][0-9]*$. "_auto", "_config" and
//            "_plonk_archived_names" are metadata and fail it, as does "0" and
//            a padded "06" (Hyprland has no such workspace).
//   name   — a string with at least one non-space character. A number, a bool,
//            an array or an object is a malformed entry, not a name.
//   auto   — the slot was named after the app it was running rather than
//            typed. Plonk reads this to decide what a move may overwrite, and
//            the service reads it to know which names may follow the app.
//
// Nothing here writes. Repair is applied to the in-memory view only, so a
// hand-edited file is rendered sanely without this plugin ever rewriting the
// user's document behind their back.

function isSlotKey(key) {
  return /^[1-9][0-9]*$/.test(String(key === undefined || key === null ? "" : key));
}

function isRealName(value) {
  return typeof value === "string" && /\S/.test(value);
}

// Control characters collapse to a space, runs of space collapse to one.
// Suggestions.clean already did this to every name on its way to the popup
// label, so a name holding a newline displayed as "Two Lines" there while
// nameFor handed back the raw "Two\nLines" — the same document read two ways
// inside one file. Doing it once, on load, settles it for both readers.
// This is display shaping only: whether a value IS a name is decided by
// isRealName above, which is the rule the shell readers share.
function cleanName(value) {
  return String(value).replace(/[\x00-\x1f\x7f]/g, " ").replace(/\s+/g, " ").trim();
}

// The one true reader. Returns the trimmed name, or "" when the slot has none.
function nameFor(names, id) {
  if (!names || typeof names !== "object") return "";
  var value = names[String(id)];
  return isRealName(value) ? cleanName(value) : "";
}

// Slot numbers carrying a real name, ascending. This is the set Plonk reserves
// and workspace-cycle steps through.
function slots(names) {
  var out = [];
  if (!names || typeof names !== "object") return out;
  for (var key in names) {
    if (!isSlotKey(key)) continue;
    if (!isRealName(names[key])) continue;
    out.push(Number(key));
  }
  out.sort(function (left, right) { return left - right; });
  return out;
}

// The "_auto" list as slot-key strings, ignoring anything malformed in it.
function autoSet(names) {
  var out = {};
  if (!names || typeof names !== "object") return out;
  var list = names._auto;
  if (!Array.isArray(list)) return out;
  for (var i = 0; i < list.length; i++) {
    var key = String(list[i]);
    if (isSlotKey(key)) out[key] = true;
  }
  return out;
}

function isAuto(names, id) {
  return autoSet(names)[String(id)] === true;
}

// A repaired in-memory copy: metadata preserved, malformed slot entries
// dropped. Anything that is not an object at all becomes an empty document,
// which the caller should treat as "unreadable" rather than "no names".
function normalize(document) {
  var out = {};
  if (!document || typeof document !== "object" || Array.isArray(document)) return out;
  for (var key in document) {
    var value = document[key];
    if (isSlotKey(key)) {
      if (isRealName(value)) out[key] = cleanName(value);
      continue;
    }
    if (key.charAt(0) === "_") out[key] = value;
  }
  return out;
}
