import { describe, test, expect, vi } from 'vitest'
import { mountHook } from '../test/hook_test_helper.js'
import AdminNav from './admin_nav.js'

function navHTML() {
  return `
    <nav>
      <a data-nav-href="/admin">Dashboard</a>
      <a data-nav-href="/admin/galls">Galls</a>
      <a data-nav-href="/admin/hosts">Hosts</a>
    </nav>
  `
}

function getLink(hook, href) {
  return hook.el.querySelector(`[data-nav-href="${href}"]`)
}

function current(hook) {
  return [...hook.el.querySelectorAll('[aria-current="page"]')].map(a => a.dataset.navHref)
}

describe('AdminNav', () => {
  test('marks /admin current only on the dashboard itself', () => {
    vi.stubGlobal('location', { pathname: '/admin' })

    const hook = mountHook(AdminNav, navHTML())
    hook.mounted()

    expect(current(hook)).toEqual(['/admin'])

    vi.unstubAllGlobals()
  })

  test('marks the section a sub-path belongs to', () => {
    vi.stubGlobal('location', { pathname: '/admin/galls/123' })

    const hook = mountHook(AdminNav, navHTML())
    hook.mounted()

    expect(current(hook)).toEqual(['/admin/galls'])
    expect(getLink(hook, '/admin').hasAttribute('aria-current')).toBe(false)

    vi.unstubAllGlobals()
  })

  test('moves the mark when the page changes', () => {
    vi.stubGlobal('location', { pathname: '/admin/hosts' })

    const hook = mountHook(AdminNav, navHTML())
    hook.mounted()
    expect(current(hook)).toEqual(['/admin/hosts'])

    vi.stubGlobal('location', { pathname: '/admin/galls' })
    hook.updated()

    expect(current(hook)).toEqual(['/admin/galls'])

    vi.unstubAllGlobals()
  })
})
