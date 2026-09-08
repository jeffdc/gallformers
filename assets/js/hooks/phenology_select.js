import { phenologyState } from './phenology_state'
import { createClock } from './seasonal_clock'

// Owns the "Selection mode" controls beneath the chart:
//   • Click & drag  → the chart brush drives the selection (no inputs here)
//   • Date range    → a center date ± N days (circular DOY window)
//   • Seasonal landmark → a date ± days at a reference latitude, projected
//                         across latitudes using the prediction clock.
//
// The modes are mutually exclusive. On any input the hook recomputes the
// selection and publishes it to phenologyState; the table / species list /
// CSV link all filter through phenologyState.applySelection. This is a
// display-only lens — it never touches the prediction windows.
//
// Host is phx-update="ignore" so typed values survive LV re-renders; the
// hook manages show/hide of the per-mode input groups itself.

export default {
  mounted() {
    this.clock = createClock(JSON.parse(this.el.dataset.landmarks))
    this._onChange = () => this.publish()
    this.el.addEventListener('input', this._onChange)
    this.el.addEventListener('change', this._onChange)
    this._onClear = () => {
      this.el.querySelector('input[value="click_drag"]').checked = true
      this.publish()
    }
    document.addEventListener('phenology:clear-brush', this._onClear)
    this.publish()
  },

  destroyed() {
    this.el.removeEventListener('input', this._onChange)
    this.el.removeEventListener('change', this._onChange)
    document.removeEventListener('phenology:clear-brush', this._onClear)
    // Leaving the explorer: drop any lens so a later remount starts clean.
    phenologyState.setSelection({ mode: 'click_drag' })
  },

  currentMode() {
    const checked = this.el.querySelector('input[name="phenology-sel-mode"]:checked')
    return checked ? checked.value : 'click_drag'
  },

  readNum(sel) {
    const el = this.el.querySelector(`[data-sel="${sel}"]`)
    if (!el || el.value === '') return null
    const n = parseFloat(el.value)
    return Number.isFinite(n) ? n : null
  },

  readDoy() {
    const el = this.el.querySelector('[data-sel="date"]')
    if (!el || !el.value) return null
    const d = new Date(el.value + 'T00:00:00Z')
    if (Number.isNaN(d.getTime())) return null
    // Keep the existing plotted DOY convention, including leap-year dates.
    return Math.floor((Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()) -
      Date.UTC(d.getUTCFullYear(), 0, 0)) / 86400000)
  },

  // Show only the input groups relevant to the active mode. A group can
  // belong to several modes (space-separated), e.g. the shared date input.
  syncGroups(mode) {
    this.el.querySelectorAll('[data-sel-group]').forEach((g) => {
      const modes = g.dataset.selGroup.split(' ')
      g.classList.toggle('hidden', !modes.includes(mode))
    })
  },

  publish() {
    const mode = this.currentMode()
    this.syncGroups(mode)
    const error = this.el.querySelector('[data-sel-error]')
    error.classList.add('hidden')

    if (mode === 'date_range') {
      phenologyState.setSelection({
        mode: 'date_range',
        doy: this.readDoy(),
        days: this.readNum('days'),
      })
    } else if (mode === 'seasonal_landmark') {
      const doy = this.readDoy()
      const lat = this.readNum('lat')
      const days = this.readNum('days')
      const window = this.clock.window(doy, lat, days)
      error.classList.toggle('hidden', window !== null)
      // Keep the reference inputs for CSV; the server recomputes the same edges.
      phenologyState.setSelection({mode, clock: this.clock, window, doy, lat, days})
    } else {
      phenologyState.setSelection({ mode: 'click_drag' })
    }
  },
}
