import { describe, test, expect, beforeEach, afterEach } from 'vitest'
import { mountHook, getPushedEvents } from '../test/hook_test_helper.js'
import Palette from './palette.js'

// The markup PaletteLive renders when open, reduced to what the hook reads.
const OPEN = `
  <div id="palette">
    <input id="palette-q" />
    <a id="palette-row-0" href="/id" aria-selected="false">Identify</a>
    <a id="palette-row-1" href="/galls" aria-selected="true">Browse galls</a>
  </div>`

describe('Palette hook', () => {
  let hook
  beforeEach(() => { document.body.innerHTML = ''; hook = mountHook(Palette, OPEN); hook.mounted() })
  afterEach(() => hook.destroyed())

  test('gf:open-palette opens the palette', () => {
    window.dispatchEvent(new CustomEvent('gf:open-palette'))
    expect(getPushedEvents(hook)).toContainEqual({ event: 'open', payload: {} })
  })

  test('Enter in the field follows the selected row', () => {
    let clicked = null
    hook.el.querySelector('#palette-row-1').addEventListener('click', e => { e.preventDefault(); clicked = e.target.id })

    const enter = new KeyboardEvent('keydown', { key: 'Enter', bubbles: true, cancelable: true })
    hook.el.querySelector('#palette-q').dispatchEvent(enter)

    expect(clicked).toBe('palette-row-1')
    expect(enter.defaultPrevented).toBe(true)
  })

  // The arrows move the selection (PaletteLive's phx-window-keydown). In a
  // text field the browser's own ↑ also moves the caret to the start (↓ to
  // the end), so the next letters typed went in front of the query.
  test('↑ and ↓ in the field leave the caret where it is', () => {
    const field = hook.el.querySelector('#palette-q')

    for (const key of ['ArrowUp', 'ArrowDown']) {
      const arrow = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })
      field.dispatchEvent(arrow)
      expect(arrow.defaultPrevented).toBe(true)
    }
  })

  test('↑ and ↓ still reach the window, where the palette moves the selection', () => {
    const seen = []
    const onKey = e => seen.push(e.key)
    window.addEventListener('keydown', onKey)

    for (const key of ['ArrowUp', 'ArrowDown']) {
      hook.el.querySelector('#palette-q').dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }))
    }

    window.removeEventListener('keydown', onKey)
    expect(seen).toEqual(['ArrowUp', 'ArrowDown'])
  })

  test('other keys in the field are left alone', () => {
    for (const key of ['a', 'ArrowLeft', 'ArrowRight', 'Home', 'Backspace']) {
      const press = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })
      hook.el.querySelector('#palette-q').dispatchEvent(press)
      expect(press.defaultPrevented).toBe(false)
    }
  })

  test('the selected row is kept in view', () => {
    const row = hook.el.querySelector('#palette-row-1')
    let scrolled = false
    row.scrollIntoView = () => { scrolled = true }
    hook.updated()
    expect(scrolled).toBe(true)
  })

  test('after destroy, the event does nothing', () => {
    hook.destroyed()
    window.dispatchEvent(new CustomEvent('gf:open-palette'))
    expect(getPushedEvents(hook)).toEqual([])
    hook.mounted()
  })
})
