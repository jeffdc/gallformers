import { phenologyState, escapeHtml, readPoints, applySelection } from './phenology_state'

// Tables own their HTML and use the chart's shared client-side selection.
// CSV is the no-JavaScript/full-result fallback; DOM caps keep large sets usable.
const OBS_ROW_CAP = 50
const SPECIES_ROW_CAP = 200

export default {
  mounted() {
    this._unsubscribe = phenologyState.subscribe(() => this.render())

    // Clicking a species-table column header sorts by that column. Delegated
    // on the host so it survives innerHTML re-renders. The server round-trips
    // sort_species → new data-sort/-dir on the host → updated() re-renders
    // (one source of truth), so we don't re-sort locally here.
    this._onHeaderActivate = (e) => {
      if (e.type === 'keydown' && e.key !== 'Enter' && e.key !== ' ') return
      const th = e.target.closest('th[data-sort-key], th[data-obs-sort-key]')
      if (!th || !this.el.contains(th)) return
      if (e.type === 'keydown') e.preventDefault()
      if (th.dataset.obsSortKey) {
        const key = th.dataset.obsSortKey
        this._obsDir = this._obsSort === key && this._obsDir === 'asc' ? 'desc' : 'asc'
        this._obsSort = key
        this.render()
        return
      }
      const key = th.dataset.sortKey
      // Re-clicking the active column flips direction; a new column starts in
      // its natural direction (name asc, the numeric/date columns desc).
      const dir =
        key === this.el.dataset.sort
          ? this.el.dataset.sortDir === 'asc'
            ? 'desc'
            : 'asc'
          : defaultDir(key)
      this.pushEvent('sort_species', { sort: key, dir })
    }
    this.el.addEventListener('click', this._onHeaderActivate)
    this.el.addEventListener('keydown', this._onHeaderActivate)

    this.render()
  },

  updated() {
    this.render()
  },

  destroyed() {
    if (this._unsubscribe) this._unsubscribe()
    if (this._onHeaderActivate) {
      this.el.removeEventListener('click', this._onHeaderActivate)
      this.el.removeEventListener('keydown', this._onHeaderActivate)
    }
  },

  render() {
    const points = readPoints()
    const filtered = applySelection(points)
    const mode = this.el.dataset.mode || 'table'

    if (mode === 'species') {
      this.el.innerHTML = renderSpeciesTable(
        filtered,
        this.el.dataset.sort || 'name',
        this.el.dataset.sortDir || 'asc',
      )
    } else {
      this.el.innerHTML = renderObsTable(filtered, this._obsSort, this._obsDir)
    }
  },
}

// ---------------------------------------------------------------------
// Obs table
// ---------------------------------------------------------------------

const OBS_HEADERS = [
  ['Species', 'species_name'], ['Phenophase', 'phenophase'], ['Lifestage', 'lifestage'],
  ['Viability', 'viability'], ['Host', 'host_species_name'], ['DOY', 'doy'], ['Date', 'date'],
  ['Lat', 'lat'], ['Lng', 'lng'], ['Source', 'source_url'], ['Page', 'page_url'],
]

export function sortObservationRows(points, key, dir = 'asc') {
  if (!OBS_HEADERS.some(([, k]) => k === key)) return points.slice()
  const numeric = ['doy', 'lat', 'lng'].includes(key)
  const missing = v => v == null || v === '' || (numeric && !Number.isFinite(Number(v)))
  const sign = dir === 'desc' ? -1 : 1
  return points.slice().sort((a, b) => {
    const av = a[key], bv = b[key]
    if (missing(av) || missing(bv)) return Number(missing(av)) - Number(missing(bv))
    // ISO dates sort chronologically; DOY and coordinates sort numerically.
    return sign * (numeric ? Number(av) - Number(bv) : String(av).localeCompare(String(bv)))
  })
}

function renderObsTable(points, sort, dir) {
  const total = points.length
  const shown = Math.min(total, OBS_ROW_CAP)
  const head = OBS_HEADERS.map(([label, key]) => {
    const active = key === sort
    const aria = active ? (dir === 'desc' ? 'descending' : 'ascending') : 'none'
    const arrow = active ? (dir === 'desc' ? ' ▼' : ' ▲') : ''
    return `<th data-obs-sort-key="${key}" role="button" tabindex="0" aria-sort="${aria}" title="Sort by ${label}" style="cursor:pointer;user-select:none;white-space:nowrap">${label}${arrow}</th>`
  }).join('')
  const body = sortObservationRows(points, sort, dir).slice(0, OBS_ROW_CAP).map(obsRow).join('')
  return `
    ${truncationNotice(shown, total, 'observations')}
    <table id="phenology-obs-table" class="gf-table gf-table-compact gf-table-zebra">
      <thead><tr>${head}</tr></thead>
      <tbody id="phenology-obs-table-body">${body}</tbody>
    </table>
  `
}

function truncationNotice(shown, total, noun) {
  if (total <= shown) return ''
  return (
    `<div style="padding: 6px 10px; font-size: 12px; color: #555; ` +
    `background: #f5f3ec; border-bottom: 1px solid #ddd;">` +
    `Showing ${shown} of ${total} ${noun}. Use the CSV download for the full set.` +
    `</div>`
  )
}

function obsRow(o) {
  return (
    '<tr>' +
    `<td><a href="/gall/${encodeURIComponent(o.species_id)}">${escapeHtml(o.species_name)}</a></td>` +
    cell(orDash(o.phenophase)) +
    cell(orDash(o.lifestage)) +
    cell(orDash(o.viability)) +
    cell(orDash(o.host_species_name)) +
    cell(o.doy) +
    cell(o.date || '') +
    cell(formatCoord(o.lat)) +
    cell(formatCoord(o.lng)) +
    linkCell(o.source_url) +
    linkCell(o.page_url, true) +
    '</tr>'
  )
}

function cell(value) {
  return `<td>${escapeHtml(value)}</td>`
}

export function isInatObservation(url) {
  try {
    const parsed = new URL(url)
    return ['http:', 'https:'].includes(parsed.protocol) &&
      ['inaturalist.org', 'www.inaturalist.org'].includes(parsed.hostname) &&
      /^\/observations\/\d+(?:\/|$)/.test(parsed.pathname)
  } catch { return false }
}

function linkCell(url, page = false) {
  try {
    if (!['http:', 'https:'].includes(new URL(url).protocol)) return '<td>—</td>'
  } catch { return '<td>—</td>' }
  if (page && isInatObservation(url)) {
    return `<td><a href="${escapeHtml(url)}" target="_blank" rel="noopener" title="Open iNaturalist observation" aria-label="Open iNaturalist observation">iNat</a></td>`
  }
  return `<td><a href="${escapeHtml(url)}" target="_blank" rel="noopener">link</a></td>`
}

function orDash(v) {
  return v == null || v === '' ? '—' : v
}

function formatCoord(c) {
  if (typeof c !== 'number') return ''
  return c.toFixed(3).replace(/\.?0+$/, '')
}

// ---------------------------------------------------------------------
// Species list (one row per species with obs count)
// ---------------------------------------------------------------------

function renderSpeciesTable(points, sort, dir) {
  const groups = new Map()
  for (const p of points) {
    const g = groups.get(p.species_id)
    if (g) {
      g.n_obs += 1
      if (p.date && p.date > g.last_date) g.last_date = p.date
    } else {
      groups.set(p.species_id, {
        species_id: p.species_id,
        name: p.species_name,
        n_obs: 1,
        last_date: p.date || '',
      })
    }
  }

  const rows = Array.from(groups.values())
  sortSpeciesRows(rows, sort, dir)

  const total = rows.length
  const shown = Math.min(total, SPECIES_ROW_CAP)
  const body = rows
    .slice(0, SPECIES_ROW_CAP)
    .map(
      (r) =>
        `<tr>
          <td><a href="/gall/${encodeURIComponent(r.species_id)}">${escapeHtml(r.name)}</a></td>
          <td>${r.n_obs}</td>
          <td>${escapeHtml(r.last_date || '—')}</td>
        </tr>`,
    )
    .join('')

  return `
    ${truncationNotice(shown, total, 'species')}
    <table id="phenology-species-table" class="gf-table gf-table-compact gf-table-zebra">
      <thead><tr>${speciesHeader(sort, dir)}</tr></thead>
      <tbody>${body}</tbody>
    </table>
  `
}

// The columns are the sort keys — clicking a header sorts by it, and
// re-clicking flips direction (no separate control). Server sort_species
// mirrors these keys; defaultDir mirrors PhenologyFilters.default_sort_dir/1.
const SPECIES_COLS = [
  ['Species', 'name'],
  ['Observations', 'obs_count'],
  ['Latest', 'recency'],
]

function defaultDir(key) {
  return key === 'name' ? 'asc' : 'desc'
}

function speciesHeader(sort, dir) {
  return SPECIES_COLS.map(([label, key]) => {
    const active = key === sort
    const arrow = active ? (dir === 'asc' ? ' ▲' : ' ▼') : ''
    const style = `cursor:pointer;user-select:none;white-space:nowrap;${active ? 'font-weight:700;' : ''}`
    const ariaSort = active ? (dir === 'asc' ? 'ascending' : 'descending') : 'none'
    return (
      `<th data-sort-key="${key}" role="button" tabindex="0" aria-sort="${ariaSort}" ` +
      `title="Sort by ${escapeHtml(label)}" style="${style}">${escapeHtml(label)}${arrow}</th>`
    )
  }).join('')
}

// Matches the CSV controller's ordering (name is the stable ascending
// tiebreaker; `dir` flips the primary key). sign = +1 asc, -1 desc.
function sortSpeciesRows(rows, sort, dir) {
  const byName = (a, b) => (a.name || '').localeCompare(b.name || '')
  const sign = dir === 'asc' ? 1 : -1
  switch (sort) {
    case 'obs_count':
      rows.sort((a, b) => sign * (a.n_obs - b.n_obs) || byName(a, b))
      break
    case 'recency':
      rows.sort((a, b) => sign * (a.last_date || '').localeCompare(b.last_date || '') || byName(a, b))
      break
    default:
      rows.sort((a, b) => sign * byName(a, b))
  }
}
