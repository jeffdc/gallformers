import { describe, test, expect } from 'vitest'
import { select } from 'd3-selection'
import { scaleLinear } from 'd3-scale'
import Chart from './phenology_chart'
import { phenologyState } from './phenology_state'

function render(prediction) {
  const el = document.createElement('div')
  el.dataset.predictions = JSON.stringify([prediction])
  const svg = select(el).append('svg')
  const hook = {
    el, _predictionG: svg.append('g'), _predictionLinesG: svg.append('g'),
    _predictionLabelsG: svg.append('g'),
    _x: scaleLinear().domain([0, 365]).range([0, 365]),
    _y: scaleLinear().domain([30, 40]).range([100, 0]), _width: 365
  }
  Chart.drawPredictions.call(hook)
  return el
}

describe('phenology prediction semantics', () => {
  test('both views emphasize viable or insect-stage records, above ordinary points and after hover', () => {
    for (const selectionEnabled of ['true', 'false']) {
      const el = document.createElement('div')
      Object.defineProperties(el, {clientWidth: {value: 800}, clientHeight: {value: 540}})
      el.dataset.selectionEnabled = selectionEnabled
      const points = [
        {viability: 'viable', phenophase: 'dormant'},
        {lifestage: null, phenophase: 'dormant'},
        {lifestage: 'Larva', phenophase: 'developing'},
        {viability: 'not viable', lifestage: ' ', phenophase: 'dormant'},
        {lifestage: 'Adult', phenophase: 'dormant'},
        {viability: 'viable', phenophase: 'developing'},
        {lifestage: '', phenophase: 'developing'}
      ].map((p, id) => ({id, lat: 35, doy: 150, generation: 'agamic', ...p}))
      el.dataset.points = JSON.stringify(points)
      const hook = {...Chart, el}
      hook.renderChart()
      const dots = [...el.querySelectorAll('.obs')]
      expect(dots.map(d => d.__data__.id)).toEqual([1, 3, 6, 0, 2, 4, 5])
      expect(JSON.parse(el.dataset.points)).toEqual(points)
      for (const dot of dots) {
        const expected = [0, 2, 4, 5].includes(dot.__data__.id) ? '1' : '0.25'
        expect(dot.parentNode.getAttribute('opacity')).toBe(expected)
        expect(dot.getAttribute('fill-opacity')).toBe('1')
        expect(dot.getAttribute('stroke-opacity')).toBe('1')
        dot.dispatchEvent(new MouseEvent('mouseover', {bubbles: true}))
        expect(dot.getAttribute('fill-opacity')).toBe('1')
        expect(el.querySelectorAll('.observation-hover')).toHaveLength(1)
        expect(el.querySelector('.observation-hover').style.pointerEvents).toBe('none')
        dot.dispatchEvent(new MouseEvent('mouseout', {bubbles: true}))
        expect(dot.parentNode.getAttribute('opacity')).toBe(expected)
        expect(el.querySelectorAll('.observation-hover')).toHaveLength(0)
      }
      hook.renderChart(true)
      expect(el.querySelectorAll('.observation-layer[opacity="1"] .obs')).toHaveLength(4)
      hook.destroyed()
    }
  })

  test('both views omit senescent dots and legend entries without removing input records or predictions', () => {
    for (const selectionEnabled of ['true', 'false']) {
      const el = document.createElement('div')
      Object.defineProperties(el, {clientWidth: {value: 800}, clientHeight: {value: 540}})
      el.dataset.selectionEnabled = selectionEnabled
      const oldGall = {lat: 35, doy: 250, generation: 'agamic', phenophase: 'senescent'}
      const freshGall = {lat: 35, doy: 150, generation: 'sexgen', phenophase: 'developing'}
      const prediction = {event: 'rearing', generation: 'agamic', target_lat: 35,
        low_doy: 245, high_doy: 255,
        contours: [{lat: 34, low_doy: 240, high_doy: 250}, {lat: 36, low_doy: 250, high_doy: 260}]}
      el.dataset.predictions = JSON.stringify([prediction])
      const hook = {...Chart, el}

      for (const points of [[oldGall, freshGall], [oldGall]]) {
        el.dataset.points = JSON.stringify(points)
        hook.renderChart()
        expect(JSON.parse(el.dataset.points)).toEqual(points)
        expect(JSON.parse(el.dataset.predictions)).toEqual([prediction])
        expect(el.querySelectorAll('.obs')).toHaveLength(points.length - 1)
        const legend = [...el.querySelectorAll('.legend text')].map(node => node.textContent)
        expect(legend).not.toContain('Senescent')
        expect(legend.includes('Developing')).toBe(points.length === 2)
        expect(el.querySelectorAll('.prediction-boundary')).toHaveLength(2)
        expect(el.querySelectorAll('.prediction-date-marker')).toHaveLength(2)
      }

      el.dataset.predictions = '[]'
      hook.renderChart()
      expect(el.textContent).toContain('No observations to display')
      expect(el.querySelector('svg')).toBeNull()
      hook.destroyed()
    }
  })

  test('both views use identical muted points and foreground interval lines without hiding records', () => {
    const styles = []
    for (const selectionEnabled of ['true', 'false']) {
      const el = document.createElement('div')
      Object.defineProperties(el, {clientWidth: {value: 800}, clientHeight: {value: 540}})
      el.dataset.selectionEnabled = selectionEnabled
      el.dataset.points = JSON.stringify(Array.from({length: 500}, (_, i) => ({
        lat: 35 + i / 1000, doy: 150, generation: 'sexgen', phenophase: 'developing'
      })))
      const rows = [35, 35.5].map(lat => ({lat, low_doy: 145, high_doy: 155,
        outer_low_doy: 140, outer_high_doy: 160, median_doy: 150}))
      el.dataset.predictions = JSON.stringify([{event: 'emergence', generation: 'sexgen',
        target_lat: 35.25, low_doy: 145, high_doy: 155, contours: rows}])
      const hook = {...Chart, el}
      hook.renderChart()
      const points = [...el.querySelectorAll('.obs')]
      expect(points).toHaveLength(500)
      const point = points[0]
      styles.push(['d', 'fill-opacity', 'stroke-opacity', 'stroke-width']
        .map(attr => point.getAttribute(attr)))
      expect(point.getAttribute('fill-opacity')).toBe('1')
      expect(point.getAttribute('stroke-opacity')).toBe('1')
      const layer = point.parentNode
      expect(layer.getAttribute('opacity')).toBe('0.25')
      expect(layer.querySelectorAll('.obs')).toHaveLength(500)
      const parent = layer.parentNode
      const children = [...parent.children]
      expect(children.indexOf(el.querySelector('.prediction-overlay'))).toBeLessThan(children.indexOf(layer))
      expect(children.indexOf(el.querySelector('.prediction-lines'))).toBeGreaterThan(children.indexOf(el.querySelector('.observation-hover-layer')))
      expect(el.querySelector('.prediction-lines').getAttribute('pointer-events')).toBe('none')
      expect(el.querySelector('.prediction-lines').getAttribute('clip-path'))
        .toBe(el.querySelector('.prediction-overlay').getAttribute('clip-path'))
      expect(el.querySelectorAll('.prediction-boundary-halo')).toHaveLength(2)
      const edge = el.querySelector('.prediction-boundary')
      const halo = el.querySelector('.prediction-boundary-halo')
      expect(halo.getAttribute('stroke')).toBe('white')
      expect(halo.getAttribute('stroke-dasharray')).toBe(edge.getAttribute('stroke-dasharray'))

      point.dispatchEvent(new MouseEvent('mouseover', {bubbles: true}))
      expect(point.getAttribute('fill-opacity')).toBe('1')
      expect(point.getAttribute('stroke-opacity')).toBe('1')
      expect(document.querySelector('.phenology-tooltip').style.visibility).toBe('visible')
      point.dispatchEvent(new MouseEvent('mouseout', {bubbles: true}))
      expect(layer.getAttribute('opacity')).toBe('0.25')
      expect(el.querySelectorAll('.observation-hover')).toHaveLength(0)

      expect(document.querySelector('.phenology-tooltip').style.display).toBe('none')

      el.dataset.predictions = '[]'
      hook.drawPredictions()
      expect(el.querySelectorAll('.prediction-boundary, .prediction-boundary-halo, .prediction-median')).toHaveLength(0)
      expect(el.querySelectorAll('.obs')).toHaveLength(500)
      hook.destroyed()
    }
    expect(styles[0]).toEqual(styles[1])
  })

  test('compact chart has no brush, preserves explorer selection, and includes the target latitude', () => {
    const el = document.createElement('div')
    Object.defineProperties(el, {clientWidth: {value: 550}, clientHeight: {value: 420}})
    el.dataset.selectionEnabled = 'false'
    el.dataset.points = JSON.stringify([
      {lat: 35, doy: 140, generation: 'sexgen', phenophase: 'developing'},
      {lat: null, doy: 150, phenophase: 'developing'}])
    el.dataset.predictions = JSON.stringify([{event: 'onset', generation: 'sexgen', target_lat: 45,
      low_doy: 150, high_doy: 150,
      contours: [{lat: 35, low_doy: 140, high_doy: 140}, {lat: 45, low_doy: 150, high_doy: 150}]}])
    const selected = {doy_min: 100, doy_max: 200, lat_min: 30, lat_max: 40}
    phenologyState.setBrush(selected)
    const hook = {...Chart, el}
    hook.renderChart()
    expect(el.querySelectorAll('.brush')).toHaveLength(0)
    expect(el.querySelectorAll('.obs')).toHaveLength(1)
    expect(el.querySelectorAll('.prediction-date-marker')).toHaveLength(1)
    expect(phenologyState.brush).toEqual(selected)
    expect(hook._y.domain()[1]).toBeGreaterThan(45)
    hook.destroyed()
    phenologyState.setBrush(null)
  })

  test('compact chart with no plottable coordinates reports no observations', () => {
    const el = document.createElement('div')
    el.dataset.selectionEnabled = 'false'
    el.dataset.points = JSON.stringify([{lat: null, doy: 140}])
    const hook = {...Chart, el}
    hook.renderChart()
    expect(el.textContent).toContain('No observations to display')
    expect(el.querySelector('svg')).toBeNull()
    hook.destroyed()
  })

  test('onset draws one line and date, without any duration band or median', () => {
    const el = render({event: 'onset', generation: 'unknown', target_lat: 35,
      low_doy: 150, high_doy: 150,
      contours: [{lat: 30, low_doy: 140, high_doy: 140}, {lat: 40, low_doy: 160, high_doy: 160}]})
    expect(el.querySelectorAll('.prediction-boundary')).toHaveLength(1)
    expect(el.querySelectorAll('.prediction-median')).toHaveLength(0)
    expect(el.querySelectorAll('.prediction-outer-band')).toHaveLength(0)
    expect(el.querySelectorAll('.prediction-date-marker')).toHaveLength(1)
    expect([...el.querySelectorAll('path')].some(p => p.getAttribute('d').endsWith('Z'))).toBe(false)
    expect(el.querySelector('.prediction-boundary').getAttribute('stroke-dasharray')).toBeNull()
  })

  test('winter uses translated narrow polygons, not a December-to-January year-wide fill', () => {
    const el = render({event: 'emergence', generation: 'agamic', wrap_year: true,
      target_lat: 35, low_doy: 360, high_doy: 10,
      contours: [{lat: 30, low_doy: -5, high_doy: 10}, {lat: 40, low_doy: -10, high_doy: 5}]})
    const paths = [...el.querySelectorAll('.prediction-boundary')]
    expect(paths).toHaveLength(10)
    expect(paths.every(p => p.getAttribute('stroke-dasharray') === '6,4')).toBe(true)
    const polygons = [...el.querySelectorAll('path')].filter(p => p.getAttribute('d').endsWith('Z'))
    expect(polygons).toHaveLength(5)
    for (const p of polygons) {
      const coords = p.getAttribute('d').match(/-?\d+(?:\.\d+)?/g).map(Number)
      const xs = coords.filter((_, i) => i % 2 === 0)
      expect(Math.max(...xs) - Math.min(...xs)).toBeLessThan(30)
    }
  })

  test('mobile layout puts the legend above the plot and uses readable quarterly ticks', () => {
    const el = document.createElement('div')
    Object.defineProperties(el, {clientWidth: {value: 340}, clientHeight: {value: 540}})
    el.dataset.points = JSON.stringify([{lat: 35, doy: 140, generation: 'sexgen', phenophase: 'developing'}])
    const hook = {...Chart, el}
    hook.renderChart()
    expect(hook._width).toBe(272)
    expect([...el.querySelectorAll('.month-axis .tick text')].map(t => t.textContent))
      .toEqual(['Jan', 'Apr', 'Jul', 'Oct'])
    expect([...el.querySelectorAll('.legend text')].every(t => Number(t.getAttribute('y')) < 0)).toBe(true)
    hook.destroyed()
  })
})
