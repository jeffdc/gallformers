import {describe, test, expect} from 'vitest'
import Select from './phenology_select'
import Chart from './phenology_chart'
import CsvLink from './phenology_csv_link'
import Chrome from './phenology_chrome'
import {phenologyState, applySelection} from './phenology_state'

function setup() {
  document.body.innerHTML = `<div id="phenology-chart"></div><div id="controls">
    <input name="phenology-sel-mode" type="radio" value="click_drag" checked>
    <input name="phenology-sel-mode" type="radio" value="date_range">
    <input name="phenology-sel-mode" type="radio" value="seasonal_landmark">
    <div data-sel-group="date_range seasonal_landmark"><input type="date" data-sel="date" value="2023-12-21"></div>
    <div data-sel-group="date_range seasonal_landmark"><input type="number" data-sel="days" value="15"></div>
    <div data-sel-group="seasonal_landmark"><input type="number" data-sel="lat" value="40"></div>
    <p data-sel-error class="hidden"></p></div><a id="csv" data-href-base="/phenology/export.csv?display=table"></a>
    <div id="chrome"></div>`
  const el = document.querySelector('#controls')
  el.dataset.landmarks = JSON.stringify([[25, 60, 300], [40, 90, 270], [55, 120, 240]])
  const chart = document.querySelector('#phenology-chart')
  Object.defineProperties(chart, {clientWidth: {value: 800}, clientHeight: {value: 540}})
  const points = [345, 355, 5, 6, 200].map(doy => ({doy, lat: 40, phenophase: 'developing'}))
  chart.dataset.points = JSON.stringify(points)
  const chartHook = {...Chart, el: chart}
  chartHook.renderChart()
  const selectHook = {...Select, el}
  selectHook.mounted()
  const csv = {...CsvLink, el: document.querySelector('#csv')}
  csv.mounted()
  const chrome = {...Chrome, el: document.querySelector('#chrome')}
  chrome.mounted()
  return {el, chartHook, selectHook, csv, points, cleanup: () => {
    selectHook.destroyed(); csv.destroyed(); chrome.destroyed(); chartHook.destroyed()
    phenologyState.setBrush(null)
    document.body.innerHTML = ''
  }}
}

describe('landmark selection workflow', () => {
  test('one window drives winter shading, table selection, count and CSV without changing predictions', () => {
    const state = setup()
    try {
      state.el.querySelector('[value="seasonal_landmark"]').checked = true
      state.selectHook.publish()
      state.chartHook.drawSelectionOverlay()
      expect(applySelection(state.points).map(p => p.doy)).toEqual([345, 355, 5])
      expect(document.querySelector('#phenology-brush-count').textContent).toContain('3 in selection')
      const url = new URL(state.csv.el.href)
      expect(url.searchParams.get('sel_mode')).toBe('seasonal_landmark')
      expect(url.searchParams.get('sel_doy')).toBe('355')
      expect(url.searchParams.get('sel_lat')).toBe('40')
      expect(url.searchParams.get('sel_days')).toBe('15')
      expect(url.searchParams.has('sel_thr')).toBe(false)
      const overlay = state.chartHook.el.querySelector('.selection-overlay')
      expect(overlay.getAttribute('clip-path')).toBe('url(#phenology-chart-prediction-clip)')
      expect(overlay.querySelectorAll('.landmark-selection-band')).toHaveLength(5)
      expect(overlay.querySelectorAll('.landmark-selection-edge')).toHaveLength(10)
      for (const band of overlay.querySelectorAll('.landmark-selection-band')) {
        const numbers = band.getAttribute('d').match(/-?\d+(?:\.\d+)?/g).map(Number)
        const xs = numbers.filter((_, i) => i % 2 === 0)
        expect(Math.max(...xs) - Math.min(...xs)).toBeLessThan(state.chartHook._width / 3)
      }
      document.querySelector('#phenology-brush-clear').click()
      expect(state.selectHook.currentMode()).toBe('click_drag')
      expect(applySelection(state.points)).toEqual(state.points)
      expect(new URL(state.csv.el.href).searchParams.has('sel_mode')).toBe(false)
    } finally { state.cleanup() }
  })

  test('invalid references select nothing with a visible message; full-year selection has no false edges', () => {
    const state = setup()
    try {
      state.el.querySelector('[value="seasonal_landmark"]').checked = true
      state.el.querySelector('[data-sel="lat"]').value = '60'
      state.selectHook.publish()
      state.chartHook.drawSelectionOverlay()
      expect(applySelection(state.points)).toEqual([])
      expect(state.el.querySelector('[data-sel-error]').classList.contains('hidden')).toBe(false)
      expect(state.chartHook.el.querySelectorAll('.landmark-selection-band')).toHaveLength(0)
      expect(new URL(state.csv.el.href).searchParams.get('sel_lat')).toBe('60')
      state.el.querySelector('[data-sel="lat"]').value = '40'
      state.el.querySelector('[data-sel="days"]').value = '183'
      state.selectHook.publish()
      state.chartHook.drawSelectionOverlay()
      expect(applySelection(state.points)).toEqual(state.points)
      expect(state.chartHook.el.querySelectorAll('.landmark-selection-band')).toHaveLength(1)
      expect(state.chartHook.el.querySelectorAll('.landmark-selection-edge')).toHaveLength(0)
    } finally { state.cleanup() }
  })
})
