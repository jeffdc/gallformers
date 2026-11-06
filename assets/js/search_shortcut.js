// Search keys. With the command palette on the page (#palette, PaletteLive),
// `/` and `s` open it (`gf:open-palette`, which its hook sends to the
// palette). Without it, a search field's `shortcut` key (search_field renders
// data-shortcut on its input) focuses that field. Never while the visitor is
// typing somewhere else or holding a modifier.

const TYPING = 'input, textarea, select, [contenteditable=""], [contenteditable="true"]'
const PALETTE_KEYS = ['/', 's']

function visible(el) {
  if (el.closest('[hidden]')) return false
  return typeof el.checkVisibility === 'function' ? el.checkVisibility() : true
}

export function handleSearchShortcut(event, doc = document) {
  if (event.metaKey || event.ctrlKey || event.altKey) return false
  const active = doc.activeElement
  if (active && active !== doc.body && active.matches(TYPING)) return false

  if (doc.getElementById('palette') && PALETTE_KEYS.includes(event.key)) {
    event.preventDefault()
    doc.defaultView.dispatchEvent(new CustomEvent('gf:open-palette'))
    return true
  }

  const field = [...doc.querySelectorAll('input[data-shortcut]')]
    .find(el => el.dataset.shortcut === event.key && visible(el))
  if (!field) return false

  event.preventDefault()
  field.focus()
  return true
}

export function installSearchShortcut(win = window) {
  win.addEventListener('keydown', event => handleSearchShortcut(event, win.document))
}
