import { describe, test, expect, beforeEach } from 'vitest'
import { mountHook, getPushedEvents } from '../test/hook_test_helper.js'
import PhotoViewer from './photo_viewer.js'

// The markup photo_viewer renders, reduced to what the hook reads.
function viewerHTML(count = 3) {
  const slides = [...Array(count).keys()]
  return `
    <div data-count="${count}" tabindex="0">
      ${slides.map(i => `
        <figure data-slide="${i}" ${i ? 'hidden' : ''}>
          <button type="button" data-open data-stage>open ${i}</button>
        </figure>`).join('')}
      <button type="button" data-prev>prev</button>
      <button type="button" data-next>next</button>
      <span data-counter>1 / ${count}</span>
      <button type="button" data-open-details>Details</button>
      <div data-thumbs>
        ${slides.map(i => `<button type="button" data-go="${i}" aria-current="${i === 0}"></button>`).join('')}
      </div>
      <dialog data-lightbox>
        <span data-counter>1 / ${count}</span>
        <button type="button" data-close>close</button>
        <div data-stage>
          ${slides.map(i => `<figure data-full="${i}" ${i ? 'hidden' : ''}><img data-src="/p${i}.jpg" alt="" /></figure>`).join('')}
        </div>
      </dialog>
      <dialog data-details>
        <button type="button" data-close>close</button>
        ${slides.map(i => `<dl data-info="${i}" ${i ? 'hidden' : ''}></dl>`).join('')}
      </dialog>
    </div>`
}

// jsdom doesn't implement HTMLDialogElement fully.
function stubDialogs(hook) {
  hook.el.querySelectorAll('dialog').forEach(d => {
    d.showModal = function () { this.open = true }
    d.close = function () {
      this.open = false
      this.dispatchEvent(new Event('close'))
    }
  })
}

function mount(count = 3) {
  const hook = mountHook(PhotoViewer, viewerHTML(count))
  stubDialogs(hook)
  hook.mounted()
  return hook
}

const shown = (hook, attr) =>
  [...hook.el.querySelectorAll(`[${attr}]`)].filter(e => !e.hidden).map(e => e.getAttribute(attr))

const click = (el) => el.dispatchEvent(new MouseEvent('click', { bubbles: true }))
const key = (el, k) => el.dispatchEvent(new KeyboardEvent('keydown', { key: k, bubbles: true }))

describe('PhotoViewer moving', () => {
  let hook
  beforeEach(() => { document.body.innerHTML = ''; hook = mount() })

  test('next and previous move, wrapping at both ends', () => {
    click(hook.el.querySelector('[data-next]'))
    expect(shown(hook, 'data-slide')).toEqual(['1'])

    click(hook.el.querySelector('[data-prev]'))
    click(hook.el.querySelector('[data-prev]'))
    expect(shown(hook, 'data-slide')).toEqual(['2'])
  })

  test('a thumbnail goes to its photo and is marked current', () => {
    click(hook.el.querySelector('[data-go="2"]'))

    expect(shown(hook, 'data-slide')).toEqual(['2'])
    expect(hook.el.querySelector('[data-go="2"]').getAttribute('aria-current')).toBe('true')
    expect(hook.el.querySelector('[data-go="0"]').getAttribute('aria-current')).toBe('false')
  })

  test('every move updates the counters, the full-size view and the details', () => {
    click(hook.el.querySelector('[data-next]'))

    hook.el.querySelectorAll('[data-counter]').forEach(c => expect(c.textContent).toBe('2 / 3'))
    expect(shown(hook, 'data-full')).toEqual(['1'])
    expect(shown(hook, 'data-info')).toEqual(['1'])
  })

  test('arrow keys move', () => {
    key(hook.el, 'ArrowRight')
    expect(shown(hook, 'data-slide')).toEqual(['1'])
    key(hook.el, 'ArrowLeft')
    key(hook.el, 'ArrowLeft')
    expect(shown(hook, 'data-slide')).toEqual(['2'])
  })

  test('every move pushes gallery_index_changed', () => {
    click(hook.el.querySelector('[data-next]'))
    expect(getPushedEvents(hook)).toContainEqual({ event: 'gallery_index_changed', payload: { index: 1 } })
  })

  test('a swipe moves: left to the next, right to the previous', () => {
    const stage = hook.el.querySelector('[data-stage]')
    const swipe = (from, to) => {
      stage.dispatchEvent(Object.assign(new Event('pointerdown', { bubbles: true }), { clientX: from }))
      stage.dispatchEvent(Object.assign(new Event('pointerup', { bubbles: true }), { clientX: to }))
    }

    swipe(300, 200)
    expect(shown(hook, 'data-slide')).toEqual(['1'])
    swipe(200, 300)
    expect(shown(hook, 'data-slide')).toEqual(['0'])
  })

  test('a single photo does not move', () => {
    document.body.innerHTML = ''
    const one = mount(1)
    key(one.el, 'ArrowRight')
    expect(shown(one, 'data-slide')).toEqual(['0'])
    expect(getPushedEvents(one)).toEqual([])
  })
})

describe('PhotoViewer dialogs', () => {
  let hook
  beforeEach(() => { document.body.innerHTML = ''; hook = mount() })

  test('clicking the photo opens the full-size view at the current photo, loading it', () => {
    click(hook.el.querySelector('[data-next]'))
    click(hook.el.querySelector('[data-slide="1"] [data-open]'))

    expect(hook.el.querySelector('[data-lightbox]').open).toBe(true)
    expect(hook.el.querySelector('[data-full="1"] img').getAttribute('src')).toBe('/p1.jpg')
  })

  test('Details opens the current photo\'s details', () => {
    click(hook.el.querySelector('[data-open-details]'))
    expect(hook.el.querySelector('[data-details]').open).toBe(true)
  })

  test('closing returns focus to what opened it', () => {
    const opener = hook.el.querySelector('[data-open-details]')
    opener.focus()
    click(opener)
    click(hook.el.querySelector('[data-details] [data-close]'))

    expect(hook.el.querySelector('[data-details]').open).toBe(false)
    expect(document.activeElement).toBe(opener)
  })

  test('arrow keys move inside the full-size view too', () => {
    click(hook.el.querySelector('[data-slide="0"] [data-open]'))
    key(hook.el.querySelector('[data-lightbox]'), 'ArrowRight')

    expect(shown(hook, 'data-full')).toEqual(['1'])
    expect(hook.el.querySelector('[data-full="1"] img').getAttribute('src')).toBe('/p1.jpg')
  })

  test('Escape closes the full-size view wherever focus is', () => {
    click(hook.el.querySelector('[data-slide="0"] [data-open]'))
    document.body.focus()
    key(document.body, 'Escape')

    expect(hook.el.querySelector('[data-lightbox]').open).toBe(false)
  })

  test('Escape closes the details too, and does nothing with no dialog open', () => {
    click(hook.el.querySelector('[data-open-details]'))
    key(document.body, 'Escape')
    expect(hook.el.querySelector('[data-details]').open).toBe(false)

    expect(() => key(document.body, 'Escape')).not.toThrow()
  })
})
