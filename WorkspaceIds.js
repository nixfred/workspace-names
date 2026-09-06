// Render live workspaces, not a fixed set of empty buttons or saved labels.
function visible(live, fallback, focusedId) {
  var ids = []
  function add(value) {
    var id = Number(value)
    if (id > 0 && id <= 10 && Math.floor(id) === id && ids.indexOf(id) === -1) ids.push(id)
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
