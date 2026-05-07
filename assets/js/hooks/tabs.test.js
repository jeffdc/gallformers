import { describe, test, expect, beforeEach } from 'vitest'
import { mountHook } from '../test/hook_test_helper.js'
import Tabs from './tabs.js'

function tabsHTML(defaultTab = 'one') {
  return `
    <div data-default-tab="${defaultTab}">
      <button data-tab-id="one" aria-selected="false">Tab One</button>
      <button data-tab-id="two" aria-selected="false">Tab Two</button>
      <button data-tab-id="three" aria-selected="false">Tab Three</button>
      <div data-tab-panel="one">Panel One</div>
      <div data-tab-panel="two">Panel Two</div>
      <div data-tab-panel="three">Panel Three</div>
    </div>
  `
}

function keydown(element, key) {
  element.dispatchEvent(new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true }))
}

function getTab(hook, id) {
  return hook.el.querySelector(`[data-tab-id="${id}"]`)
}

function getPanel(hook, id) {
  return hook.el.querySelector(`[data-tab-panel="${id}"]`)
}

describe('Tabs', () => {
  let hook

  beforeEach(() => {
    hook = mountHook(Tabs, tabsHTML('one'))
    hook.mounted()
  })

  test('mounted activates default tab', () => {
    expect(getTab(hook, 'one').getAttribute('aria-selected')).toBe('true')
    expect(getTab(hook, 'one').hasAttribute('data-active')).toBe(true)
    expect(getPanel(hook, 'one').hasAttribute('data-active')).toBe(true)
  })

  test('non-default tabs are inactive', () => {
    expect(getTab(hook, 'two').getAttribute('aria-selected')).toBe('false')
    expect(getPanel(hook, 'two').hasAttribute('data-active')).toBe(false)
  })

  test('clicking a tab activates it and deactivates others', () => {
    getTab(hook, 'two').click()

    expect(getTab(hook, 'two').getAttribute('aria-selected')).toBe('true')
    expect(getPanel(hook, 'two').hasAttribute('data-active')).toBe(true)
    expect(getTab(hook, 'one').getAttribute('aria-selected')).toBe('false')
    expect(getPanel(hook, 'one').hasAttribute('data-active')).toBe(false)
  })

  test('ArrowRight moves to next tab', () => {
    keydown(getTab(hook, 'one'), 'ArrowRight')

    expect(getTab(hook, 'two').getAttribute('aria-selected')).toBe('true')
  })

  test('ArrowLeft moves to previous tab', () => {
    keydown(getTab(hook, 'two'), 'ArrowLeft')

    expect(getTab(hook, 'one').getAttribute('aria-selected')).toBe('true')
  })

  test('ArrowRight wraps from last to first', () => {
    keydown(getTab(hook, 'three'), 'ArrowRight')

    expect(getTab(hook, 'one').getAttribute('aria-selected')).toBe('true')
  })

  test('ArrowLeft wraps from first to last', () => {
    keydown(getTab(hook, 'one'), 'ArrowLeft')

    expect(getTab(hook, 'three').getAttribute('aria-selected')).toBe('true')
  })

  test('Home goes to first tab', () => {
    getTab(hook, 'three').click()
    keydown(getTab(hook, 'three'), 'Home')

    expect(getTab(hook, 'one').getAttribute('aria-selected')).toBe('true')
  })

  test('End goes to last tab', () => {
    keydown(getTab(hook, 'one'), 'End')

    expect(getTab(hook, 'three').getAttribute('aria-selected')).toBe('true')
  })

  test('updated preserves active tab after DOM patch', () => {
    getTab(hook, 'two').click()

    // Simulate LiveView DOM patch stripping data-active attributes
    hook.el.querySelectorAll('[data-active]').forEach(el => el.removeAttribute('data-active'))
    hook.updated()

    expect(getTab(hook, 'two').hasAttribute('data-active')).toBe(true)
    expect(getPanel(hook, 'two').hasAttribute('data-active')).toBe(true)
    expect(getPanel(hook, 'one').hasAttribute('data-active')).toBe(false)
  })
})
