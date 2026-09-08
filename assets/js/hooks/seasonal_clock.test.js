import {describe, test, expect} from 'vitest'
import {readFileSync} from 'node:fs'
import {URL as NodeURL} from 'node:url'
import {createClock, inWindow} from './seasonal_clock'
import {applySeasonalLandmark} from './phenology_state'

const rows = readFileSync(new NodeURL('../../../priv/phenology/seasonal_landmarks.csv', import.meta.url), 'utf8')
  .trim().split('\n').slice(1).map(row => row.split(',').slice(0, 3).map(Number))
const clock = createClock(rows)

describe('shared seasonal-landmark clock', () => {
  test('reference landmarks and continuous forward/inverse coordinates agree', () => {
    for (const [lat, spring, autumn] of rows) {
      expect(clock.coordinate(spring, lat)).toBeCloseTo(0, 8)
      expect(clock.coordinate(autumn, lat)).toBeCloseTo(182.5, 8)
    }
    for (const lat of [25, 30.13, 40, 50.9, 55]) {
      for (const day of [-180, 1, 90, 180, 270, 365, 550]) {
        const phase = clock.coordinate(day, lat)
        expect(clock.inverse(phase, lat)).toBeCloseTo(day, 8)
        expect(clock.coordinate(day + 365, lat)).toBeCloseTo(phase + 365, 8)
      }
    }
  })

  test('reference days define both edges and transfer across supported latitudes', () => {
    for (const day of [1, 90, 180, 270, 355, 366]) {
      for (const lat of [25, 37.5, 55]) {
        const window = clock.window(day, lat, 10)
        expect(clock.inverse(window.low, lat)).toBeCloseTo(day - 10, 8)
        expect(clock.inverse(window.high, lat)).toBeCloseTo(day + 10, 8)
        expect(inWindow(window.low, window)).toBe(true)
        expect(inWindow(window.high, window)).toBe(true)
        expect(inWindow(window.low - 0.001, window)).toBe(false)
        expect(inWindow(window.high + 0.001, window)).toBe(false)
        for (const other of [25, 40, 55]) {
          const projected = clock.inverse(clock.coordinate(day, lat), other)
          const wrapped = projected - Math.floor((projected - 1) / 365) * 365
          const point = {doy: wrapped, lat: other, seasind: null}
          expect(applySeasonalLandmark([point], {clock, window})).toEqual([point])
        }
      }
    }
  })

  test('winter, exact dates, full-year windows and invalid inputs are explicit', () => {
    const winter = clock.window(355, 40, 15)
    expect(inWindow(clock.coordinate(5, 40), winter)).toBe(true)
    expect(inWindow(clock.coordinate(6, 40), winter)).toBe(false)
    const exact = clock.window(120, 40, 0)
    expect(inWindow(clock.coordinate(120, 40), exact)).toBe(true)
    expect(inWindow(clock.coordinate(121, 40), exact)).toBe(false)
    const wholeYear = clock.window(180, 40, 183)
    for (let day = 1; day <= 366; day++) expect(inWindow(clock.coordinate(day, 40), wholeYear)).toBe(true)
    for (const args of [[0, 40, 10], [367, 40, 10], [null, 40, 10], [100, 60, 10],
      [100, 40, null], [100, 40, -1], [100, 40, 184], [100, 40, Infinity]]) {
      expect(clock.window(...args)).toBeNull()
    }
    expect(applySeasonalLandmark([{doy: 120, lat: 20}], {clock, window: wholeYear})).toEqual([])
    expect(applySeasonalLandmark([{doy: 120, lat: 40}], {clock, window: null})).toEqual([])
    expect(() => createClock([])).toThrow('Invalid seasonal-landmark reference')
  })
})
