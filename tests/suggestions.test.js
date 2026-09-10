const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const api = {};
vm.createContext(api);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../Suggestions.js'), 'utf8'), api);
const client = (id, title, app = 'foot', focus = 0) => ({workspace: {id}, title, class: app, focusHistoryID: focus});

// A suggestion is the app, never the window title.
assert.equal(api.fromClients([client(1, 'vic: workspaces', 'kitty')])['1'], 'Kitty');
assert.equal(api.fromClients([client(1, '(2) Posts / X - Brave', 'brave-browser')])['1'], 'Brave');
assert.equal(api.fromClients([client(3, '✳ Network Pulse plugin')])['3'], 'Foot');
assert.equal(api.fromClients([client(4, 'Hermes', 'Hermes')])['4'], 'Hermes');
assert.equal(api.fromClients([client(5, 'Downloads', 'org.gnome.Nautilus')])['5'], 'Files');
assert.equal(api.fromClients([client(6, 'x', 'io.github.lgse.Strata')])['6'], 'Strata');
assert.equal(api.fromClients([client(7, 'x', 'some-thing_else')])['7'], 'Some Thing Else');
assert.equal(api.fromClients([client(8, 'x', 'code')])['8'], 'VS Code');

// The desktop entry's own name wins over the class-derived one, and a
// lowercase entry name is capitalised. A lookup that throws or finds nothing
// falls back to the class.
const resolve = cls => ({ Hermes: 'Hermes', kitty: 'kitty', 'com.example.Longname': 'Example Studio' })[cls] || '';
assert.equal(api.fromClients([client(1, 'x', 'kitty')], resolve)['1'], 'Kitty');
assert.equal(api.fromClients([client(1, 'x', 'com.example.Longname')], resolve)['1'], 'Example Studio');
assert.equal(api.fromClients([client(1, 'x', 'unknown-tool')], resolve)['1'], 'Unknown Tool');
assert.equal(api.fromClients([client(1, 'x', 'kitty')], () => { throw new Error('no entries') })['1'], 'Kitty');
// The known table outranks a desktop entry that says something longer.
assert.equal(api.fromClients([client(1, 'x', 'brave-browser')], () => 'Brave Web Browser')['1'], 'Brave');

// The most recently focused window names the workspace.
assert.equal(api.fromClients([client(1, 'Older', 'kitty', 5), client(1, 'Current', 'brave-browser', 0)])['1'], 'Brave');
assert.equal(api.fromClients([client(1, 'Older', 'brave-browser', 0), client(1, 'Current', 'kitty', 5)])['1'], 'Brave');

// A very long entry name is shortened like any other label.
assert.equal(api.fromClients([client(1, 'x', 'x')], () => 'A'.repeat(50))['1'].length, 36);

assert.equal(api.label({'1': 'My name'}, {'1': 'Automatic'}, 1), 'My name');
assert.equal(api.label({}, {'1': 'Automatic'}, 1), 'Automatic');
assert.equal(Object.keys(api.fromClients([client(-99, 'Scratchpad')])).length, 0);
assert.equal(Object.keys(api.fromClients([{workspace: {id: 2}, title: 'x', class: '', mapped: true}])).length, 0, 'no class, no suggestion');
assert.equal(Object.keys(api.fromClients([{workspace: {id: 2}, title: 'x', class: 'kitty', mapped: false}])).length, 0, 'unmapped windows do not count');
const before = api.fromClients([client(7, 'Project Seven', 'kitty')]);
const after = api.fromClients([client(2, 'Project Seven', 'kitty')]);
assert.equal(before['7'], after['2']);
assert.equal(after['7'], undefined, 'no stale suggestion after Plonk renumbering');
assert.equal(Object.keys(api.fromClients([])).length, 0, 'closed windows clear suggestions');
console.log('Suggestion tests passed');
