import { describe, test, expect, beforeEach } from 'vitest'
import { handleSearchShortcut } from './search_shortcut.js'

function key(k, opts = {}) {
  return new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true, ...opts })
}

describe('handleSearchShortcut', () => {
  beforeEach(() => {
    document.body.innerHTML = `
      <input id="other" type="text" />
      <input id="search" type="search" data-shortcut="/" />
    `
  })

  test('the shortcut key focuses the search field and is not typed', () => {
    const event = key('/')
    expect(handleSearchShortcut(event, document)).toBe(true)
    expect(document.activeElement.id).toBe('search')
    expect(event.defaultPrevented).toBe(true)
  })

  test('does nothing while typing in another field', () => {
    document.getElementById('other').focus()
    expect(handleSearchShortcut(key('/'), document)).toBe(false)
    expect(document.activeElement.id).toBe('other')
  })

  test('ignores other keys and modified keys', () => {
    expect(handleSearchShortcut(key('a'), document)).toBe(false)
    expect(handleSearchShortcut(key('/', { metaKey: true }), document)).toBe(false)
    expect(document.activeElement).toBe(document.body)
  })

  test('skips a hidden field and uses the first visible one', () => {
    document.body.innerHTML = `
      <div hidden><input id="hidden" type="search" data-shortcut="/" /></div>
      <input id="visible" type="search" data-shortcut="/" />
    `
    expect(handleSearchShortcut(key('/'), document)).toBe(true)
    expect(document.activeElement.id).toBe('visible')
  })
})

describe('the command palette', () => {
  let opened
  beforeEach(() => {
    document.body.innerHTML = `
      <input id="other" type="text" />
      <div id="palette"></div>
      <input id="search" type="search" data-shortcut="/" />
    `
    opened = 0
    window.addEventListener('gf:open-palette', () => { opened++ })
  })

  test('/ and s open it, rather than focusing a field', () => {
    const slash = key('/')
    expect(handleSearchShortcut(slash, document)).toBe(true)
    expect(slash.defaultPrevented).toBe(true)
    expect(handleSearchShortcut(key('s'), document)).toBe(true)
    expect(opened).toBe(2)
    expect(document.activeElement).toBe(document.body)
  })

  test('not while typing in a field, nor with a modifier', () => {
    document.getElementById('other').focus()
    expect(handleSearchShortcut(key('s'), document)).toBe(false)
    document.getElementById('other').blur()
    expect(handleSearchShortcut(key('s', { ctrlKey: true }), document)).toBe(false)
    expect(opened).toBe(0)
  })
})
