import { describe, test, expect, vi, beforeEach, afterEach } from 'vitest'
import { mountHook } from '../test/hook_test_helper.js'
import SourceReader from './source_reader.js'

const body = (find, cited, inner) =>
  `<div data-find="${find}" data-cited="${cited}">${inner}</div>`

describe('SourceReader', () => {
  let scrolled

  beforeEach(() => {
    document.body.innerHTML = ''
    scrolled = []
    vi.spyOn(Element.prototype, 'scrollIntoView').mockImplementation(function () { scrolled.push(this.id) })
  })

  afterEach(() => { vi.restoreAllMocks() })

  test('mounted brings the first quoted block into view', () => {
    const hook = mountHook(SourceReader, body('', '#/texts/2', '<p id="a">A</p><p id="b" data-cited>B</p><p id="c" data-cited>C</p>'))
    hook.mounted()
    expect(scrolled).toEqual(['b'])
  })

  test('a new find brings its first match into view', () => {
    const hook = mountHook(SourceReader, body('', 'x', '<p id="a" data-cited>A</p><p id="b">B</p>'))
    hook.mounted()
    hook.el.dataset.find = 'oak'
    hook.el.innerHTML = '<p id="a" data-cited>A</p><p id="b">B <mark id="m">oak</mark></p>'
    hook.updated()
    expect(scrolled).toEqual(['a', 'm'])
  })

  test('an update that changes neither the find nor the question leaves the scroll alone', () => {
    const hook = mountHook(SourceReader, body('', 'x', '<p id="a" data-cited>A</p>'))
    hook.mounted()
    hook.updated()
    expect(scrolled).toEqual(['a'])
  })

  test('a find with no match falls back to the quoted block', () => {
    const hook = mountHook(SourceReader, body('', 'x', '<p id="a" data-cited>A</p>'))
    hook.mounted()
    hook.el.dataset.find = 'nothing'
    hook.updated()
    expect(scrolled).toEqual(['a', 'a'])
  })
})
