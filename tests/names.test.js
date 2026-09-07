const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const api = {};
vm.createContext(api);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../Names.js'), 'utf8'), api);

// Values built inside the vm sandbox carry that realm's prototypes, so a
// strict deep-equal compares realms rather than contents. Compare the JSON.
const same = (actual, expected, message) =>
  message === undefined
    ? assert.equal(JSON.stringify(actual), JSON.stringify(expected))
    : assert.equal(JSON.stringify(actual), JSON.stringify(expected), message);

// A slot is a key like "5". Metadata and impossible workspace numbers are not.
assert.equal(api.isSlotKey('5'), true);
assert.equal(api.isSlotKey('12'), true);
assert.equal(api.isSlotKey('_auto'), false, '_auto is metadata, not a workspace');
assert.equal(api.isSlotKey('_config'), false);
assert.equal(api.isSlotKey('_plonk_archived_names'), false);
assert.equal(api.isSlotKey('0'), false, 'Hyprland numbers workspaces from 1');
assert.equal(api.isSlotKey('06'), false, 'a padded key is not the workspace 6');
assert.equal(api.isSlotKey('-3'), false, 'a negative id is a Hyprland-named workspace');
assert.equal(api.isSlotKey(''), false);

// A name is a non-blank STRING. This is the rule the shell readers already
// enforced and the QML side did not.
assert.equal(api.isRealName('Brave'), true);
assert.equal(api.isRealName('   '), false, 'whitespace reserves nothing');
assert.equal(api.isRealName(''), false);
assert.equal(api.isRealName(42), false, 'a number is a malformed entry, not a name');
assert.equal(api.isRealName(true), false);
assert.equal(api.isRealName(['Arr']), false);
assert.equal(api.isRealName({ o: 1 }), false);
assert.equal(api.isRealName(null), false);

// nameFor is the single reader both QML files now use. Before this it ran
// String() over whatever it found, so these four returned "42", "true", "Arr"
// and "[object Object]" — names visible in the bar that Plonk would not carry,
// would not reserve a slot for, and workspace-cycle would not stop on.
const messy = { 1: 'Real', 2: 42, 3: '   ', 4: true, 5: ['Arr'], 6: { o: 1 }, 7: '  Padded  ' };
assert.equal(api.nameFor(messy, 1), 'Real');
assert.equal(api.nameFor(messy, 2), '', 'a number must not render as a name');
assert.equal(api.nameFor(messy, 3), '');
assert.equal(api.nameFor(messy, 4), '');
assert.equal(api.nameFor(messy, 5), '');
assert.equal(api.nameFor(messy, 6), '');
assert.equal(api.nameFor(messy, 7), 'Padded', 'a real name is trimmed');
assert.equal(api.nameFor(messy, 9), '', 'an unnamed workspace has no name');
assert.equal(api.nameFor(null, 1), '', 'a missing document is not a crash');
assert.equal(api.nameFor('nonsense', 1), '');

// slots() is the set Plonk reserves and workspace-cycle walks.
same(api.slots(messy), [1, 7]);
same(api.slots({ 10: 'Ten', 2: 'Two', 1: 'One' }), [1, 2, 10], 'numeric order, not string order');
same(api.slots({ _auto: ['1'], _config: { hold: 750 } }), [], 'metadata is never a slot');
same(api.slots({}), []);
same(api.slots(null), []);

// _auto marks the slots named from a window title rather than typed.
same(api.autoSet({ 1: 'A', _auto: ['1', '2'] }), { 1: true, 2: true });
assert.equal(api.isAuto({ 1: 'A', _auto: ['1'] }, 1), true);
assert.equal(api.isAuto({ 1: 'A', _auto: ['1'] }, 2), false);
assert.equal(api.isAuto({ 1: 'A' }, 1), false, 'no _auto means nothing is automatic');
same(api.autoSet({ _auto: 'not-an-array' }), {}, 'a malformed _auto is ignored');
same(api.autoSet({ _auto: ['_config', '0', '3'] }), { 3: true }, 'junk inside _auto is dropped');

// normalize() repairs the in-memory view and keeps metadata. It must never be
// used to rewrite the file: this plugin reads the document, it does not own it.
const normalized = api.normalize({
  1: 'Real', 2: 42, 3: '  ', 4: '  Trimmed  ',
  _auto: ['1'], _config: { hold: 750 }, _plonk_archived_names: [{ name: 'Old', workspace: '9' }],
  '06': 'padded', 0: 'zero'
});
same(normalized, {
  1: 'Real', 4: 'Trimmed',
  _auto: ['1'], _config: { hold: 750 }, _plonk_archived_names: [{ name: 'Old', workspace: '9' }]
});
same(api.normalize([]), {}, 'an array document is unreadable, not a name set');
same(api.normalize('nope'), {});
same(api.normalize(null), {});

// The realistic document from this machine survives untouched.
const live = { 1: 'Brave', 2: 'Imprint', 3: 'Sonos', 4: 'Weather', 5: 'x.com', 6: 'Pi', _auto: ['5', '6'] };
same(api.normalize(live), live, 'a good document is not altered');
same(api.slots(live), [1, 2, 3, 4, 5, 6]);

// Control characters collapse to a space and runs of space collapse to one, so
// nameFor agrees with the popup label instead of handing back a raw newline.
assert.equal(api.nameFor({ 3: 'Two\nLines' }, 3), 'Two Lines', 'a newline must not survive into a name');
assert.equal(api.nameFor({ 3: 'a\tb' }, 3), 'a b');
assert.equal(api.nameFor({ 3: '  spaced   out  ' }, 3), 'spaced out');
assert.equal(api.nameFor({ 3: '\u0007bell' }, 3), 'bell', 'a leading control character is not a name character');
assert.equal(api.isRealName('\n'), false, 'a lone newline reserves nothing');
same(api.slots({ 3: '\n' }), [], 'a control-only value is not a name');
same(api.normalize({ 3: 'Two\nLines' }), { 3: 'Two Lines' }, 'normalize cleans the same way');

console.log('Names tests passed');
