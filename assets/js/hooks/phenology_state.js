// Shared client-side selection for the chart, table, count and CSV link.
// Selection gestures never round-trip through LiveView.
import { inWindow } from './seasonal_clock'

const listeners = new Set()

export const phenologyState = {
  // Current chart-brush bounds in data domain: {doy_min, doy_max, lat_min,
  // lat_max} or null when no brush is active.
  brush: null,

  // Active selection lens:
  //   { mode: 'click_drag' }                       → use the chart brush
  //   { mode: 'date_range',   doy, days }          → circular DOY window
  //   { mode: 'seasonal_landmark', clock, window } → shared-clock band
  // Modes are mutually exclusive (a radio picks one), matching the Shiny
  // app. The landmark edges come from a date ± days at a reference latitude.
  selection: { mode: 'click_drag' },

  setBrush(b) {
    this.brush = b
    listeners.forEach((fn) => fn())
  },

  setSelection(s) {
    this.selection = s || { mode: 'click_drag' }
    listeners.forEach((fn) => fn())
  },

  // Returns an unsubscribe function. Callers (e.g. the table hook) call it
  // from their `destroyed` lifecycle so we don't accumulate dead listeners
  // across LV navigations.
  subscribe(fn) {
    listeners.add(fn)
    return () => listeners.delete(fn)
  },
}

// Read the obs array off the chart hook's data-points attribute. All
// chrome/table hooks render from this same in-memory array — same data
// the tooltip uses, which is why their updates feel instant.
export function readPoints() {
  const chartEl = document.getElementById('phenology-chart')
  if (!chartEl) return []
  try {
    return JSON.parse(chartEl.dataset.points || '[]')
  } catch (e) {
    return []
  }
}

// Pure JS brush filter — kept in step with the server's apply_brush in
// the CSV controller so the downloaded file matches what's on screen.
export function applyBrush(points, brush) {
  if (!brush) return points
  const { doy_min, doy_max, lat_min, lat_max } = brush
  return points.filter(
    (p) =>
      p.doy >= doy_min &&
      p.doy <= doy_max &&
      typeof p.lat === 'number' &&
      p.lat >= lat_min &&
      p.lat <= lat_max,
  )
}

// Circular day-of-year window [doy-days, doy+days] (mod 365), matching the
// legacy doyCalc "Date range" mode. Wraps across the year boundary.
export function applyDateRange(points, { doy, days }) {
  if (doy == null || days == null) return points
  const min = mod365(doy - days)
  const max = mod365(doy + days)
  return points.filter((p) =>
    min <= max ? p.doy >= min && p.doy <= max : p.doy >= min || p.doy <= max,
  )
}

// Use plotted DOY/latitude, not the legacy imported seasind column. Incomplete
// references select nothing; the controls explain what needs correcting.
export function applySeasonalLandmark(points, {clock, window}) {
  if (!clock || !window) return []
  return points.filter(p => Number.isFinite(p.doy) && p.doy >= 1 && p.doy <= 366 &&
    inWindow(clock.coordinate(p.doy, p.lat), window))
}

// The visible selection, dispatched on the active mode. Everything that
// renders the selected obs (table, species list, CSV link) filters through
// this. Mirrors the server's apply_selection in the CSV controller.
export function applySelection(points) {
  const sel = phenologyState.selection || { mode: 'click_drag' }
  switch (sel.mode) {
    case 'date_range':
      return applyDateRange(points, sel)
    case 'seasonal_landmark':
      return applySeasonalLandmark(points, sel)
    default:
      return applyBrush(points, phenologyState.brush)
  }
}

function mod365(x) {
  return ((x % 365) + 365) % 365
}

// HTML escape for any user-controlled or external-API string interpolated
// into innerHTML.
export function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g,
    (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
}
