const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const api = {};
vm.createContext(api);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../WorkspaceIds.js'), 'utf8'), api);
const ids = (...args) => Array.from(api.visible(...args));
assert.deepEqual(ids({'1': 1, '2': 1, '3': 1, '4': 1}, [{id: 5}, {id: 6}], 4), [1, 2, 3, 4], 'Plonk removes ghost 5 and stale model 6');
assert.deepEqual(ids({'1': 1, '4': 1, '6': 0}, [], 6), [1, 4, 6], 'an empty focused workspace stays selectable');
assert.deepEqual(ids({'1': 1, '7': 0}, [], 1), [1, 7], 'a workspace displayed on another monitor remains visible');
assert.deepEqual(ids(null, [{id: 3}, {id: 1}, {id: -99}], 3), [1, 3], 'startup uses compositor model until first probe');
assert.deepEqual(ids({}, [{id: 5}], 2), [2], 'an authoritative empty probe must not resurrect stale model ids');
assert.deepEqual(ids({'-99': 1, '1.5': 1, 'foo': 1, '11': 1, '10': 1}, [], 10), [10, 11]);
// A workspace above 10 is still a workspace: Hyprland hands out ids like 11
// and 13 before Plonk compacts them, and the rail used to drop them silently.
assert.deepEqual(ids({'11': 1, '13': 2}, [], 13), [11, 13]);
assert.deepEqual(ids({'9': 1, '10': 1, '11': 1, '12': 1}, [], 9), [9, 10, 11, 12]);
assert.deepEqual(ids({'-1337': 1, '-98': 1, '2': 1}, [], 2), [2], 'specials never show');
console.log('Workspace ID tests passed');
