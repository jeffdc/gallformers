import { describe, test, expect, beforeEach } from 'vitest'
import { applyTheme, setTheme, syncThemeOptions } from './theme.js'

function memoryStorage(initial = {}) {
  const data = { ...initial }
  return {
    getItem: (k) => (k in data ? data[k] : null),
    setItem: (k, v) => { data[k] = String(v) },
    removeItem: (k) => { delete data[k] },
    data
  }
}

describe('theme', () => {
  let root
  beforeEach(() => {
    root = document.documentElement
    root.removeAttribute('data-theme')
    root.removeAttribute('data-theme-choice')
    document.body.innerHTML = `
      <button data-theme-option="system" role="menuitemradio"></button>
      <button data-theme-option="light" role="menuitemradio"></button>
      <button data-theme-option="dark" role="menuitemradio"></button>`
  })

  test('with no saved choice the page follows the OS: no data-theme', () => {
    applyTheme(root, memoryStorage())
    expect(root.hasAttribute('data-theme')).toBe(false)
    expect(root.dataset.themeChoice).toBe('system')
  })

  test('a saved choice is applied', () => {
    applyTheme(root, memoryStorage({ 'gf-theme': 'dark' }))
    expect(root.dataset.theme).toBe('dark')
    expect(root.dataset.themeChoice).toBe('dark')
  })

  test('an unknown saved value is the OS setting', () => {
    applyTheme(root, memoryStorage({ 'gf-theme': 'purple' }))
    expect(root.hasAttribute('data-theme')).toBe(false)
  })

  test('choosing a theme saves it, applies it and checks its option', () => {
    const storage = memoryStorage()
    setTheme('light', root, storage)
    expect(storage.data['gf-theme']).toBe('light')
    expect(root.dataset.theme).toBe('light')
    expect(document.querySelector('[data-theme-option=light]').getAttribute('aria-checked')).toBe('true')
    expect(document.querySelector('[data-theme-option=dark]').getAttribute('aria-checked')).toBe('false')

    setTheme('system', root, storage)
    expect('gf-theme' in storage.data).toBe(false)
    expect(root.hasAttribute('data-theme')).toBe(false)
    expect(document.querySelector('[data-theme-option=system]').getAttribute('aria-checked')).toBe('true')
  })

  test('options are checked from the page state after a re-render', () => {
    root.dataset.themeChoice = 'dark'
    syncThemeOptions(document)
    expect(document.querySelector('[data-theme-option=dark]').getAttribute('aria-checked')).toBe('true')
  })

  test('storage that throws (private mode) still applies the choice for the page', () => {
    const broken = { getItem() { throw new Error('no') }, setItem() { throw new Error('no') }, removeItem() { throw new Error('no') } }
    expect(() => applyTheme(root, broken)).not.toThrow()
    setTheme('dark', root, broken)
    expect(root.dataset.theme).toBe('dark')
  })
})
