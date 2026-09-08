import { phenologyState } from './phenology_state'

// Mounted on the `Download CSV` link. The link is server-rendered (its
// existence depends on display mode + obs presence) but its href needs
// to pick up brush bounds without an LV roundtrip.
//
// On every mount/update we re-read the base href from `data-href-base`
// (the server's URL without brush params) and append the current brush
// bounds, if any. We also subscribe to `phenologyState` so brush
// gestures update the href synchronously.

export default {
  mounted() {
    this._unsubscribe = phenologyState.subscribe(() => this.applyBrush())
    this.applyBrush()
  },

  updated() {
    // Server re-rendered the link (filter changed → new base href).
    // Re-apply brush on top of the fresh base.
    this.applyBrush()
  },

  destroyed() {
    if (this._unsubscribe) this._unsubscribe()
  },

  applyBrush() {
    const base = this.el.dataset.hrefBase || this.el.getAttribute('href') || ''
    const params = new URLSearchParams()
    const sel = phenologyState.selection || { mode: 'click_drag' }

    if (sel.mode === 'date_range') {
      if (sel.doy != null) params.set('sel_mode', 'date_range')
      if (sel.doy != null) params.set('sel_doy', String(sel.doy))
      if (sel.days != null) params.set('sel_days', String(sel.days))
    } else if (sel.mode === 'seasonal_landmark') {
      // Send reference inputs, not client-computed thresholds. Invalid or
      // incomplete references receive a validation response, not a full export.
      params.set('sel_mode', 'seasonal_landmark')
      if (sel.doy != null) params.set('sel_doy', String(sel.doy))
      if (sel.lat != null) params.set('sel_lat', String(sel.lat))
      if (sel.days != null) params.set('sel_days', String(sel.days))
    } else {
      const brush = phenologyState.brush
      if (brush) {
        params.set('doy_min', String(brush.doy_min))
        params.set('doy_max', String(brush.doy_max))
        params.set('lat_min', String(brush.lat_min))
        params.set('lat_max', String(brush.lat_max))
      }
    }

    const qs = params.toString()
    if (!qs) {
      this.el.href = base
      return
    }
    const sep = base.includes('?') ? '&' : '?'
    this.el.href = base + sep + qs
  },
}
