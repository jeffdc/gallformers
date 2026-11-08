import { describe, test, expect, beforeEach } from 'vitest'
import { mountHook } from '../test/hook_test_helper.js'
import Dismissible from './dismissible.js'

const html = '<p data-key="gf-fact-hint" hidden>Hint <button data-dismiss>x</button></p>'

describe('Dismissible', () => {
  beforeEach(() => { localStorage.clear() })

  test('shows the element when it has not been dismissed', () => {
    const hook = mountHook(Dismissible, html)
    hook.mounted()

    expect(hook.el.hidden).toBe(false)
  })

  test('keeps it hidden once dismissed in this browser', () => {
    localStorage.setItem('gf-fact-hint', 'dismissed')
    const hook = mountHook(Dismissible, html)
    hook.mounted()

    expect(hook.el.hidden).toBe(true)
  })

  test('dismissing hides it and remembers it', () => {
    const hook = mountHook(Dismissible, html)
    hook.mounted()

    hook.el.querySelector('[data-dismiss]').click()

    expect(hook.el.hidden).toBe(true)
    expect(localStorage.getItem('gf-fact-hint')).toBe('dismissed')
  })

  test('a re-render that puts hidden back follows what was chosen', () => {
    const hook = mountHook(Dismissible, html)
    hook.mounted()

    hook.el.hidden = true
    hook.updated()

    expect(hook.el.hidden).toBe(false)
  })

  test('storage that throws (private browsing) shows the hint and forgets the dismissal', () => {
    const getItem = Storage.prototype.getItem
    const setItem = Storage.prototype.setItem
    Storage.prototype.getItem = () => { throw new Error('denied') }
    Storage.prototype.setItem = () => { throw new Error('denied') }

    try {
      const hook = mountHook(Dismissible, html)
      hook.mounted()
      expect(hook.el.hidden).toBe(false)

      hook.el.querySelector('[data-dismiss]').click()
      expect(hook.el.hidden).toBe(true)
    } finally {
      Storage.prototype.getItem = getItem
      Storage.prototype.setItem = setItem
    }
  })
})
