import { describe, test, expect, beforeEach, vi } from 'vitest'
import { mountHook, getPushedEvents } from '../test/hook_test_helper.js'
import SortableImages from './sortable_images.js'

function sortableHTML(ids = [10, 20, 30]) {
  const items = ids.map(id =>
    `<div data-image-id="${id}"><img src="/img/${id}.jpg" /></div>`
  ).join('')
  return `<div>${items}</div>`
}

function getItems(hook) {
  return Array.from(hook.el.querySelectorAll('[data-image-id]'))
}

function getOrder(hook) {
  return getItems(hook).map(el => parseInt(el.dataset.imageId, 10))
}

describe('SortableImages setup', () => {
  test('mounted makes all items draggable', () => {
    const hook = mountHook(SortableImages, sortableHTML())
    hook.mounted()

    getItems(hook).forEach(item => {
      expect(item.getAttribute('draggable')).toBe('true')
    })
  })

  test('updated re-applies draggable', () => {
    const hook = mountHook(SortableImages, sortableHTML())
    hook.mounted()

    // Simulate LiveView adding a new item
    const newItem = document.createElement('div')
    newItem.dataset.imageId = '40'
    hook.el.appendChild(newItem)

    hook.updated()

    expect(newItem.getAttribute('draggable')).toBe('true')
  })
})

describe('SortableImages drag start', () => {
  test('dragstart sets draggingEl and original index', () => {
    const hook = mountHook(SortableImages, sortableHTML())
    hook.mounted()

    const items = getItems(hook)
    const event = new Event('dragstart', { bubbles: true })
    event.dataTransfer = { setData: vi.fn(), effectAllowed: '' }
    items[1].dispatchEvent(event)

    expect(hook.draggingEl).toBe(items[1])
    expect(hook.originalIndex).toBe(1)
  })

  test('dragstart sets data transfer', () => {
    const hook = mountHook(SortableImages, sortableHTML())
    hook.mounted()

    const items = getItems(hook)
    const setData = vi.fn()
    const event = new Event('dragstart', { bubbles: true })
    event.dataTransfer = { setData, effectAllowed: '' }
    items[0].dispatchEvent(event)

    expect(setData).toHaveBeenCalledWith('text/plain', '10')
  })
})

describe('SortableImages drag end', () => {
  test('pushes reorder_images when position changed', () => {
    const hook = mountHook(SortableImages, sortableHTML([10, 20, 30]))
    hook.mounted()

    const items = getItems(hook)

    // Simulate drag: pick up item 10, manually move it to the end
    hook.draggingEl = items[0]
    hook.originalIndex = 0
    items[0].classList.add('opacity-50')

    // Move in DOM: 10 goes after 30
    hook.el.appendChild(items[0])

    // Fire dragend
    const event = new Event('dragend', { bubbles: true })
    hook.handleDragEnd(event)

    // Should push new order
    const events = getPushedEvents(hook)
    const reorder = events.find(e => e.event === 'reorder_images')
    expect(reorder).toBeTruthy()
    expect(reorder.payload.order).toEqual([20, 30, 10])
  })

  test('pushes reorder_images to its own element (its LiveComponent, else the LiveView)', () => {
    const hook = mountHook(SortableImages, sortableHTML([10, 20, 30]))
    hook.mounted()

    const items = getItems(hook)
    hook.draggingEl = items[0]
    hook.originalIndex = 0
    hook.el.appendChild(items[0])

    hook.handleDragEnd(new Event('dragend', { bubbles: true }))

    const reorder = getPushedEvents(hook).find(e => e.event === 'reorder_images')
    expect(reorder.selector).toBe(hook.el)
  })

  test('does not push when position unchanged', () => {
    const hook = mountHook(SortableImages, sortableHTML([10, 20, 30]))
    hook.mounted()

    const items = getItems(hook)

    // Simulate drag that ends in same position
    hook.draggingEl = items[0]
    hook.originalIndex = 0
    items[0].classList.add('opacity-50')

    const event = new Event('dragend', { bubbles: true })
    hook.handleDragEnd(event)

    expect(getPushedEvents(hook)).toHaveLength(0)
  })

  test('removes opacity class on drag end', () => {
    const hook = mountHook(SortableImages, sortableHTML())
    hook.mounted()

    const items = getItems(hook)
    hook.draggingEl = items[0]
    hook.originalIndex = 0
    items[0].classList.add('opacity-50')

    hook.handleDragEnd(new Event('dragend', { bubbles: true }))

    expect(items[0].classList.contains('opacity-50')).toBe(false)
  })

  test('clears state on drag end', () => {
    const hook = mountHook(SortableImages, sortableHTML())
    hook.mounted()

    hook.draggingEl = getItems(hook)[0]
    hook.originalIndex = 0

    hook.handleDragEnd(new Event('dragend', { bubbles: true }))

    expect(hook.draggingEl).toBeNull()
    expect(hook.originalIndex).toBeNull()
  })
})

describe('SortableImages getItemIndex', () => {
  test('returns correct index for each item', () => {
    const hook = mountHook(SortableImages, sortableHTML([10, 20, 30]))
    hook.mounted()

    const items = getItems(hook)
    expect(hook.getItemIndex(items[0])).toBe(0)
    expect(hook.getItemIndex(items[1])).toBe(1)
    expect(hook.getItemIndex(items[2])).toBe(2)
  })
})
