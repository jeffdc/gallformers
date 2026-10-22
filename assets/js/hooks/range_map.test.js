import { describe, test, expect, vi } from 'vitest'
import RangeMap, {
  computeEffectiveSets,
  buildFillExpression,
  pickSubdivisionCode,
  setsEqual,
  forEachCoord
} from './range_map.js'
import {
  mountHook,
  pushServerEvent
} from '../test/hook_test_helper.js'

// ============================================
// computeEffectiveSets
// ============================================

describe('computeEffectiveSets', () => {
  test('in-range codes pass through when not excluded', () => {
    const inRange = new Set(['US-CA', 'US-TX'])
    const excluded = new Set()
    const inherited = new Set()

    const { effectiveInRange } = computeEffectiveSets(inRange, excluded, inherited)

    expect(effectiveInRange.has('US-CA')).toBe(true)
    expect(effectiveInRange.has('US-TX')).toBe(true)
  })

  test('excluded codes are removed from in-range', () => {
    const inRange = new Set(['US-CA', 'US-TX'])
    const excluded = new Set(['US-TX'])
    const inherited = new Set()

    const { effectiveInRange } = computeEffectiveSets(inRange, excluded, inherited)

    expect(effectiveInRange.has('US-CA')).toBe(true)
    expect(effectiveInRange.has('US-TX')).toBe(false)
  })

  test('inherited codes pass through when not in-range and not excluded', () => {
    const inRange = new Set(['US-CA'])
    const excluded = new Set()
    const inherited = new Set(['CA-AB', 'CA-BC'])

    const { effectiveInherited } = computeEffectiveSets(inRange, excluded, inherited)

    expect(effectiveInherited.has('CA-AB')).toBe(true)
    expect(effectiveInherited.has('CA-BC')).toBe(true)
  })

  test('inherited codes that are also in-range are excluded from inherited', () => {
    const inRange = new Set(['US-CA'])
    const excluded = new Set()
    const inherited = new Set(['US-CA', 'CA-AB'])

    const { effectiveInherited } = computeEffectiveSets(inRange, excluded, inherited)

    expect(effectiveInherited.has('US-CA')).toBe(false)
    expect(effectiveInherited.has('CA-AB')).toBe(true)
  })

  test('excluded codes are removed from inherited', () => {
    const inRange = new Set()
    const excluded = new Set(['CA-AB'])
    const inherited = new Set(['CA-AB', 'CA-BC'])

    const { effectiveInherited } = computeEffectiveSets(inRange, excluded, inherited)

    expect(effectiveInherited.has('CA-AB')).toBe(false)
    expect(effectiveInherited.has('CA-BC')).toBe(true)
  })

  test('empty sets return empty results', () => {
    const { effectiveInRange, effectiveInherited } = computeEffectiveSets(
      new Set(), new Set(), new Set()
    )

    expect(effectiveInRange.size).toBe(0)
    expect(effectiveInherited.size).toBe(0)
  })
})

// ============================================
// buildFillExpression
// ============================================

describe('buildFillExpression', () => {
  test('returns fallback color when all sets empty', () => {
    const result = buildFillExpression(
      new Set(), new Set(), new Set(), false, '#FFFFFF', null
    )

    expect(result).toBe('#FFFFFF')
  })

  test('builds case expression with in-range codes', () => {
    const result = buildFillExpression(
      new Set(['US-CA']), new Set(), new Set(), false, '#FFFFFF', null
    )

    expect(Array.isArray(result)).toBe(true)
    expect(result[0]).toBe('case')
    // Should contain the in-range match and fallback
    expect(result.length).toBeGreaterThan(2)
  })

  test('includes excluded codes only in editable mode', () => {
    const excluded = new Set(['US-TX'])

    const nonEditable = buildFillExpression(
      new Set(['US-CA']), new Set(), excluded, false, '#FFFFFF', null
    )

    const editable = buildFillExpression(
      new Set(['US-CA']), new Set(), excluded, true, '#FFFFFF', null
    )

    // Editable expression should be longer (has excluded condition)
    expect(editable.length).toBeGreaterThan(nonEditable.length)
  })

  test('uses color overrides when provided', () => {
    const overrides = { inRange: '#3B82F6', inheritedRange: '#93C5FD' }
    const result = buildFillExpression(
      new Set(['US-CA']), new Set(), new Set(), false, '#FFFFFF', overrides
    )

    // The expression should contain the override color, not the default
    expect(JSON.stringify(result)).toContain('#3B82F6')
  })
})

// ============================================
// pickSubdivisionCode
// ============================================

describe('pickSubdivisionCode', () => {
  test('returns null for empty features', () => {
    expect(pickSubdivisionCode([])).toBeNull()
  })

  test('prefers hyphenated code (real subdivision)', () => {
    const features = [
      { properties: { code: 'BR' } },
      { properties: { code: 'BR-AM' } }
    ]

    expect(pickSubdivisionCode(features)).toBe('BR-AM')
  })

  test('falls back to bare country code when no hyphenated code', () => {
    const features = [
      { properties: { code: 'BR' } }
    ]

    expect(pickSubdivisionCode(features)).toBe('BR')
  })

  test('returns first hyphenated code when multiple exist', () => {
    const features = [
      { properties: { code: 'BR-AM' } },
      { properties: { code: 'BR-PA' } }
    ]

    expect(pickSubdivisionCode(features)).toBe('BR-AM')
  })

  test('returns null when feature has no code', () => {
    const features = [{ properties: {} }]

    expect(pickSubdivisionCode(features)).toBeNull()
  })
})

// ============================================
// setsEqual
// ============================================

describe('setsEqual', () => {
  test('empty sets are equal', () => {
    expect(setsEqual(new Set(), new Set())).toBe(true)
  })

  test('identical sets are equal', () => {
    expect(setsEqual(new Set(['a', 'b']), new Set(['a', 'b']))).toBe(true)
  })

  test('different sizes are not equal', () => {
    expect(setsEqual(new Set(['a']), new Set(['a', 'b']))).toBe(false)
  })

  test('same size but different values are not equal', () => {
    expect(setsEqual(new Set(['a', 'b']), new Set(['a', 'c']))).toBe(false)
  })

  test('order does not matter', () => {
    expect(setsEqual(new Set(['b', 'a']), new Set(['a', 'b']))).toBe(true)
  })
})

// ============================================
// forEachCoord
// ============================================

describe('forEachCoord', () => {
  test('Point geometry', () => {
    const coords = []
    forEachCoord({ type: 'Point', coordinates: [10, 20] }, (lng, lat) => coords.push([lng, lat]))

    expect(coords).toEqual([[10, 20]])
  })

  test('MultiPoint geometry', () => {
    const coords = []
    forEachCoord(
      { type: 'MultiPoint', coordinates: [[1, 2], [3, 4]] },
      (lng, lat) => coords.push([lng, lat])
    )

    expect(coords).toEqual([[1, 2], [3, 4]])
  })

  test('LineString geometry', () => {
    const coords = []
    forEachCoord(
      { type: 'LineString', coordinates: [[1, 2], [3, 4], [5, 6]] },
      (lng, lat) => coords.push([lng, lat])
    )

    expect(coords).toHaveLength(3)
  })

  test('Polygon geometry iterates all ring coordinates', () => {
    const coords = []
    forEachCoord(
      { type: 'Polygon', coordinates: [[[0, 0], [1, 0], [1, 1], [0, 0]]] },
      (lng, lat) => coords.push([lng, lat])
    )

    expect(coords).toHaveLength(4)
  })

  test('MultiPolygon geometry iterates all polygons', () => {
    const coords = []
    forEachCoord(
      {
        type: 'MultiPolygon',
        coordinates: [
          [[[0, 0], [1, 0], [1, 1], [0, 0]]],
          [[[2, 2], [3, 2], [3, 3], [2, 2]]]
        ]
      },
      (lng, lat) => coords.push([lng, lat])
    )

    expect(coords).toHaveLength(8)
  })

  test('handles null geometry gracefully', () => {
    const coords = []
    forEachCoord(null, (lng, lat) => coords.push([lng, lat]))
    expect(coords).toHaveLength(0)
  })

  test('handles geometry with no coordinates', () => {
    const coords = []
    forEachCoord({ type: 'Point' }, (lng, lat) => coords.push([lng, lat]))
    expect(coords).toHaveLength(0)
  })
})

// ============================================
// viewport sync
// ============================================

describe('RangeMap viewport sync', () => {
  function buildHook(htmlAttrs = '') {
    const hook = mountHook(
      RangeMap,
      `<div
        data-in-range='[]'
        data-excluded-range='[]'
        data-inherited-range='[]'
        data-introduced-range='[]'
        data-editable='true'
        data-navigable='false'
        data-place-mode='false'
        ${htmlAttrs}
      ></div>`
    )

    hook.initMap = () => {}
    hook.updateChoropleth = vi.fn()
    hook.fitToRange = vi.fn()
    hook.zoomToCountry = vi.fn()
    hook.mounted()

    return hook
  }

  test('range-update preserves drill-down country viewport', () => {
    const hook = buildHook()
    hook.drillDownCountry = 'US'

    pushServerEvent(hook, 'range-update', {
      in_range: ['US-CA'],
      excluded_range: [],
      inherited_range: [],
      introduced_range: []
    })

    expect(hook.zoomToCountry).toHaveBeenCalledWith('US', true)
    expect(hook.fitToRange).not.toHaveBeenCalled()
  })

  test('updated preserves drill-down country viewport when range expands', () => {
    const hook = buildHook()
    hook.drillDownCountry = 'CA'
    hook.el.dataset.inRange = JSON.stringify(['CA-BC'])

    hook.updated()

    expect(hook.zoomToCountry).toHaveBeenCalledWith('CA', true)
    expect(hook.fitToRange).not.toHaveBeenCalled()
  })
})

// ============================================
// createMap
// ============================================

describe('RangeMap createMap', () => {
  // A browser without WebGL2 returns no context, so the real MapLibre
  // constructor throws.
  test('shows a message instead of a map when WebGL2 is unavailable', () => {
    vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockReturnValue(null)
    const hook = mountHook(RangeMap, '<div></div>')

    const map = hook.createMap({
      container: hook.el,
      style: { version: 8, sources: {}, layers: [] }
    })

    expect(map).toBeNull()
    expect(hook.el.textContent).toContain('Map unavailable in this browser')
  })
})
