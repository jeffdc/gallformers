import { describe, test, expect, beforeEach } from 'vitest'
import { mountHook, getPushedEvents } from '../test/hook_test_helper.js'
import Typeahead from './typeahead.js'

// Minimal HTML that matches the typeahead component structure
function typeaheadHTML({ results = [], searchEvent = 'search', clearEvent = 'clear', closeEvent = 'close', target = null } = {}) {
  const resultsHTML = results.map(r =>
    `<button data-typeahead-option role="option" aria-selected="false">${r}</button>`
  ).join('')

  const targetAttr = target ? `data-target="${target}"` : ''

  return `
    <div data-search-event="${searchEvent}" data-clear-event="${clearEvent}" data-close-event="${closeEvent}" ${targetAttr}>
      <input data-typeahead-input type="text" />
      <div data-typeahead-results>${resultsHTML}</div>
      <div data-typeahead-selected tabindex="0"></div>
    </div>
  `
}

function keydown(element, key) {
  const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true })
  element.dispatchEvent(event)
  return event
}

// ============================================
// Mounting
// ============================================

describe('Typeahead mounting', () => {
  test('mounted initializes highlight to -1', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    expect(hook.highlightedIndex).toBe(-1)
  })

  test('mounted attaches keydown listener to input', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    expect(hook.input).toBeTruthy()
    expect(hook.input._typeaheadListener).toBe(true)
  })

  test('mounted attaches keydown listener to selected container', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    expect(hook.selectedContainer).toBeTruthy()
    expect(hook.selectedContainer._typeaheadListener).toBe(true)
  })
})

// ============================================
// Keyboard navigation — ArrowDown / ArrowUp
// ============================================

describe('Typeahead keyboard navigation', () => {
  let hook

  beforeEach(() => {
    hook = mountHook(Typeahead, typeaheadHTML({ results: ['Oak', 'Maple', 'Birch'] }))
    hook.mounted()
  })

  test('ArrowDown moves highlight from -1 to 0', () => {
    keydown(hook.input, 'ArrowDown')

    expect(hook.highlightedIndex).toBe(0)
  })

  test('ArrowDown advances through results', () => {
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown')

    expect(hook.highlightedIndex).toBe(1)
  })

  test('ArrowDown stops at last result', () => {
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown') // past end

    expect(hook.highlightedIndex).toBe(2) // clamped to last
  })

  test('ArrowUp moves highlight up', () => {
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowUp')

    expect(hook.highlightedIndex).toBe(0)
  })

  test('ArrowUp stops at first result', () => {
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowUp')
    keydown(hook.input, 'ArrowUp') // past beginning

    expect(hook.highlightedIndex).toBe(0) // clamped to first
  })

  test('ArrowDown with no results does nothing', () => {
    const emptyHook = mountHook(Typeahead, typeaheadHTML({ results: [] }))
    emptyHook.mounted()

    keydown(emptyHook.input, 'ArrowDown')

    expect(emptyHook.highlightedIndex).toBe(-1)
  })

  test('Escape closes the open results, keeps the text and pushes nothing', () => {
    hook.input.value = 'Quercus'
    keydown(hook.input, 'Escape')

    expect(hook.resultsContainer.hidden).toBe(true)
    expect(hook.input.value).toBe('Quercus')
    expect(getPushedEvents(hook)).toEqual([])
  })

  test('typing again, or ArrowDown, opens the closed results', () => {
    keydown(hook.input, 'Escape')
    hook.input.dispatchEvent(new Event('input', { bubbles: true }))
    expect(hook.resultsContainer.hidden).toBe(false)

    keydown(hook.input, 'Escape')
    keydown(hook.input, 'ArrowDown')
    expect(hook.resultsContainer.hidden).toBe(false)
  })

  test('the results stay closed when the page updates', () => {
    keydown(hook.input, 'Escape')
    hook.updated()
    expect(hook.resultsContainer.hidden).toBe(true)
  })

  test('Escape resets highlight', () => {
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown')
    expect(hook.highlightedIndex).toBe(1)

    keydown(hook.input, 'Escape')

    expect(hook.highlightedIndex).toBe(-1)
  })
})

// ============================================
// ARIA attributes
// ============================================

describe('Typeahead ARIA highlighting', () => {
  let hook, results

  beforeEach(() => {
    hook = mountHook(Typeahead, typeaheadHTML({ results: ['Oak', 'Maple'] }))
    hook.mounted()
    results = hook.getResults()
  })

  test('highlighted item gets aria-selected=true and data-highlighted', () => {
    keydown(hook.input, 'ArrowDown')

    expect(results[0].getAttribute('aria-selected')).toBe('true')
    expect(results[0].hasAttribute('data-highlighted')).toBe(true)
  })

  test('non-highlighted items get aria-selected=false', () => {
    keydown(hook.input, 'ArrowDown')

    expect(results[1].getAttribute('aria-selected')).toBe('false')
    expect(results[1].hasAttribute('data-highlighted')).toBe(false)
  })

  test('moving highlight updates both items', () => {
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown')

    expect(results[0].getAttribute('aria-selected')).toBe('false')
    expect(results[1].getAttribute('aria-selected')).toBe('true')
  })

  test('escape clears all highlighting', () => {
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'Escape')

    expect(results[0].getAttribute('aria-selected')).toBe('false')
    expect(results[1].getAttribute('aria-selected')).toBe('false')
  })
})

// ============================================
// Enter key behaviour
// ============================================

describe('Typeahead Enter key', () => {
  test('Enter on highlighted result clicks it', () => {
    const hook = mountHook(Typeahead, typeaheadHTML({ results: ['Oak', 'Maple'] }))
    hook.mounted()

    let clicked = false
    hook.getResults()[0].addEventListener('click', () => { clicked = true })

    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'Enter')

    expect(clicked).toBe(true)
    expect(hook.highlightedIndex).toBe(-1) // reset after selection
  })

  test('Enter with text but no highlight pushes closeEvent and clears input', () => {
    const hook = mountHook(Typeahead, typeaheadHTML({ results: ['Oak'] }))
    hook.mounted()
    hook.input.value = 'something'

    keydown(hook.input, 'Enter')

    const events = getPushedEvents(hook)
    expect(events.some(e => e.event === 'close')).toBe(true)
    expect(hook.input.value).toBe('')
  })

  test('Enter with empty input and no highlight does nothing', () => {
    const hook = mountHook(Typeahead, typeaheadHTML({ results: ['Oak'] }))
    hook.mounted()
    hook.input.value = ''

    keydown(hook.input, 'Enter')

    expect(getPushedEvents(hook)).toHaveLength(0)
  })
})

// ============================================
// Selected container keyboard
// ============================================

describe('Typeahead selected container keyboard', () => {
  test('Escape pushes clearEvent and sets pendingFocus', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    keydown(hook.selectedContainer, 'Escape')

    const events = getPushedEvents(hook)
    expect(events.some(e => e.event === 'clear')).toBe(true)
    expect(hook.pendingFocus).toBe(true)
  })

  test('Backspace pushes clearEvent', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    keydown(hook.selectedContainer, 'Backspace')

    expect(getPushedEvents(hook).some(e => e.event === 'clear')).toBe(true)
  })

  test('Delete pushes clearEvent', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    keydown(hook.selectedContainer, 'Delete')

    expect(getPushedEvents(hook).some(e => e.event === 'clear')).toBe(true)
  })

  test('printable character pushes clearEvent + searchEvent with the character', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    keydown(hook.selectedContainer, 'q')

    const events = getPushedEvents(hook)
    expect(events.some(e => e.event === 'clear')).toBe(true)
    expect(events.some(e => e.event === 'search' && e.payload.value === 'q')).toBe(true)
    expect(hook.pendingFocus).toBe(true)
  })
})

// ============================================
// pushTargetedEvent routing
// ============================================

describe('Typeahead event routing', () => {
  test('without target, pushes to LiveView', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    keydown(hook.selectedContainer, 'Escape')

    const events = getPushedEvents(hook)
    const clearEvent = events.find(e => e.event === 'clear')
    expect(clearEvent).toBeTruthy()
    expect(clearEvent.selector).toBeUndefined() // pushEvent, not pushEventTo
  })

  test('with target, pushes to component', () => {
    const hook = mountHook(Typeahead, typeaheadHTML({ target: '42' }))
    hook.mounted()

    keydown(hook.selectedContainer, 'Escape')

    const events = getPushedEvents(hook)
    const clearEvent = events.find(e => e.event === 'clear')
    expect(clearEvent).toBeTruthy()
    expect(clearEvent.selector).toBe('[data-phx-component="42"]')
  })
})

// ============================================
// updated() lifecycle
// ============================================

describe('Typeahead updated', () => {
  test('does not clear the input when no server query is provided', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    hook.input.value = 'Q'
    hook.updated()

    expect(hook.input.value).toBe('Q')
  })

  test('does not clear a non-empty input when results are closed but query still exists', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    hook.el.dataset.query = 'Q'
    hook.input.value = 'Q'
    hook.updated()

    expect(hook.input.value).toBe('Q')
  })

  test('clears the input when the server-side query is reset', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    hook.el.dataset.query = ''
    hook.input.value = 'Q'
    hook.updated()

    expect(hook.input.value).toBe('')
  })

  test('focuses input when pendingFocus is true', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()
    hook.pendingFocus = true

    hook.updated()

    expect(hook.pendingFocus).toBe(false)
    expect(document.activeElement).toBe(hook.input)
  })

  test('resets highlight when results become empty', () => {
    const hook = mountHook(Typeahead, typeaheadHTML({ results: ['Oak', 'Maple'] }))
    hook.mounted()
    keydown(hook.input, 'ArrowDown')
    expect(hook.highlightedIndex).toBe(0)

    // Simulate LiveView removing all results
    hook.resultsContainer.innerHTML = ''
    hook.updated()

    expect(hook.highlightedIndex).toBe(-1)
  })

  test('clamps highlight when results shrink', () => {
    const hook = mountHook(Typeahead, typeaheadHTML({ results: ['Oak', 'Maple', 'Birch'] }))
    hook.mounted()

    // Navigate to last item
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown')
    keydown(hook.input, 'ArrowDown')
    expect(hook.highlightedIndex).toBe(2)

    // Simulate LiveView shrinking results to 1 item
    hook.resultsContainer.innerHTML = '<button data-typeahead-option>Oak</button>'
    hook.updated()

    expect(hook.highlightedIndex).toBe(0)
  })
})

// ============================================
// Input event (paste/autofill)
// ============================================

describe('Typeahead paste/autofill', () => {
  test('input event pushes searchEvent with current value', () => {
    const hook = mountHook(Typeahead, typeaheadHTML())
    hook.mounted()

    hook.input.value = 'Quercus'
    hook.input.dispatchEvent(new Event('input', { bubbles: true }))

    const events = getPushedEvents(hook)
    expect(events.some(e => e.event === 'search' && e.payload.value === 'Quercus')).toBe(true)
  })
})
