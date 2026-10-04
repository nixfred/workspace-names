// Render live workspaces, not a fixed set of empty buttons or saved labels.
//
// Every live workspace shows, whatever its number. There used to be a ceiling
// of 10 here, which hid real work: Hyprland hands out ids well above 10 (gus
// held 11 and 13 the morning of 2026-10-04) whenever a workspace is created
// before Plonk compacts the list, and the rail simply did not draw them. A
// workspace with windows in it is never the thing to hide. Specials
// (negative ids) and fractions still never appear.
function visible(live, fallback, focusedId) {
  var ids = []
  function add(value) {
    var id = Number(value)
    if (id > 0 && Math.floor(id) === id && ids.indexOf(id) === -1) ids.push(id)
  }
  if (live !== null && live !== undefined) {
    for (var key in live) add(key)
  } else {
    for (var i = 0; i < fallback.length; i++) add(fallback[i].id)
  }
  add(focusedId)
  ids.sort(function(left, right) { return left - right })
  return ids
}
