import { test, expect } from 'vitest'
import Table, { isInatObservation, sortObservationRows } from './phenology_table'

test.each([
  ['name', 'asc', ['Alpha', 'Beta']], ['name', 'desc', ['Beta', 'Alpha']],
  ['obs_count', 'asc', ['Beta', 'Alpha']], ['obs_count', 'desc', ['Alpha', 'Beta']],
  ['recency', 'asc', ['Beta', 'Alpha']], ['recency', 'desc', ['Alpha', 'Beta']],
])('species rendering sorts %s %s and uses the latest year', (sort, sortDir, names) => {
  const chart = document.createElement('div')
  chart.id = 'phenology-chart'
  chart.dataset.points = JSON.stringify([
    {species_id: 1, species_name: 'Alpha', date: '2023-12-31'},
    {species_id: 1, species_name: 'Alpha', date: '2025-01-01'},
    {species_id: 2, species_name: 'Beta', date: '2024-06-01'},
  ])
  document.body.append(chart)
  const el = document.createElement('div')
  Object.assign(el.dataset, {mode: 'species', sort, sortDir})
  try {
    Table.render.call({el})
    expect([...el.querySelectorAll('tbody a')].map(a => a.textContent)).toEqual(names)
    expect(el.querySelector('tbody').textContent).toContain('2025-01-01')
    expect(el.querySelector('tbody').textContent).not.toContain('2023-12-31')
  } finally { chart.remove() }
})

test('identifies observation destinations, not source labels or lookalike URLs', () => {
  expect(isInatObservation('https://www.inaturalist.org/observations/123')).toBe(true)
  expect(isInatObservation('https://inaturalist.org/observations/123?foo=bar')).toBe(true)
  for (const url of [null, '', 'https://www.inaturalist.org/taxa/123',
    'https://inaturalist.org.evil.test/observations/123', 'https://example.com/?url=https://inaturalist.org/observations/123',
    'https://inaturalist.org/observations/identify', 'https://bugguide.net/node/view/123']) {
    expect(isInatObservation(url)).toBe(false)
  }
})

test('DOY and coordinates sort numerically, dates chronologically, without mutating input', () => {
  const rows = [{doy: 100, lat: 40, date: '2022-01-01'}, {doy: 9, lat: 9, date: '2023-02-01'}, {doy: 30, lat: -5, date: '2021-12-31'}]
  expect(sortObservationRows(rows, 'doy').map(r=>r.doy)).toEqual([9,30,100])
  expect(sortObservationRows(rows, 'doy', 'desc').map(r=>r.doy)).toEqual([100,30,9])
  expect(sortObservationRows(rows, 'lat').map(r=>r.lat)).toEqual([-5,9,40])
  expect(sortObservationRows(rows, 'date').map(r=>r.date)).toEqual(['2021-12-31','2022-01-01','2023-02-01'])
  expect(rows.map(r=>r.doy)).toEqual([100,9,30])
})

test('empty values remain last in both directions; tied rows retain order', () => {
  const rows = [{id: 1, doy: null}, {id: 2, doy: 5}, {id: 3, doy: 5}, {id: 4, doy: ''}]
  for (const dir of ['asc','desc']) expect(sortObservationRows(rows,'doy',dir).map(r=>r.id)).toEqual([2,3,1,4])
})

test('rendering escapes external text and rejects executable page and source links', () => {
  const chart = document.createElement('div')
  chart.id = 'phenology-chart'
  chart.dataset.points = JSON.stringify([{species_id: 1,
    species_name: '<img src=x onerror=alert(1)>',
    source_url: 'javascript:alert(1)', page_url: 'data:text/html,test'}])
  document.body.append(chart)
  const el = document.createElement('div')
  try {
    Table.render.call({el})
    expect(el.querySelector('img')).toBeNull()
    expect(el.textContent).toContain('<img src=x onerror=alert(1)>')
    expect([...el.querySelectorAll('a')].map(a => a.getAttribute('href'))).toEqual(['/gall/1'])
  } finally { chart.remove() }
})

test.each(['table', 'species'])('gall names link to their GF page in %s mode', mode => {
  const chart = document.createElement('div')
  chart.id = 'phenology-chart'
  chart.dataset.points = JSON.stringify([{species_id: 817,
    species_name: 'Dryocosmus quercuspalustris (sexgen)'}])
  document.body.append(chart)
  const el = document.createElement('div')
  el.dataset.mode = mode
  try {
    Table.render.call({el})
    const link = el.querySelector('tbody tr td a')
    expect(link.getAttribute('href')).toBe('/gall/817')
    expect(link.textContent).toBe('Dryocosmus quercuspalustris (sexgen)')
  } finally { chart.remove() }
})
