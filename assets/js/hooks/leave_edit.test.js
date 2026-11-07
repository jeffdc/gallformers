import { describe, test, expect, afterEach } from 'vitest'
import { mountHook, pushServerEvent } from '../test/hook_test_helper.js'
import LeaveEdit, { withoutEdit } from './leave_edit.js'

describe('withoutEdit', () => {
  test('drops edit and photos, keeping the rest', () => {
    expect(withoutEdit('https://gallformers.org/gall/12?edit&photos&source=3#fact-9'))
      .toBe('/gall/12?source=3#fact-9')
  })

  test('drops edit alone', () => {
    expect(withoutEdit('https://gallformers.org/gall/12?edit')).toBe('/gall/12')
  })

  test('nothing to do outside Edit mode', () => {
    expect(withoutEdit('https://gallformers.org/gall/12?source=3')).toBe(null)
  })
})

describe('LeaveEdit', () => {
  afterEach(() => { window.history.replaceState(null, '', '/') })

  test('patches the page to its URL without edit when the tray applies', () => {
    window.history.replaceState(null, '', '/gall/12?edit')
    const patched = []
    const hook = mountHook(LeaveEdit, '<div id="tray"></div>')
    hook.js = () => ({ patch: (href) => patched.push(href) })
    hook.mounted()

    pushServerEvent(hook, 'leave-edit', {})

    expect(patched).toEqual(['/gall/12'])
  })

  test('does nothing on a page not in Edit mode', () => {
    window.history.replaceState(null, '', '/gall/12')
    const patched = []
    const hook = mountHook(LeaveEdit, '<div id="tray"></div>')
    hook.js = () => ({ patch: (href) => patched.push(href) })
    hook.mounted()

    pushServerEvent(hook, 'leave-edit', {})

    expect(patched).toEqual([])
  })
})
