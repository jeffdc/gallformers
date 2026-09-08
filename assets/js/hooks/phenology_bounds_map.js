/**
 * PhenologyBoundsMap Hook — MapLibre GL + PMTiles
 *
 * A bounding-box selector under the lat/lng inputs in the explorer
 * filter form. Mirrors the legacy Shiny `doyCalc` Leaflet widget.
 *
 *   - Renders country/subdivision boundaries (same PMTiles file the
 *     range_map hook already uses).
 *   - Plots phenology observations as small dots (read from the chart
 *     container's data-points), colored by generation, so the user can
 *     see where data exists before drawing a box.
 *   - Shift + drag draws a bounding box; mouseup writes the bounds into
 *     the four `min_lat` / `max_lat` / `min_lng` / `max_lng` form
 *     inputs and dispatches an `input` event so the form's phx-change
 *     fires and the LV re-runs the obs query.
 *   - Plain drag pans, scroll zooms — boxZoom is disabled so it doesn't
 *     conflict with shift+drag.
 *   - `updated()` re-syncs the rectangle from the host's data-min-lat
 *     etc. attrs, so URL deep-links and typed input values both reflect
 *     onto the map.
 *
 * Host data attrs:
 *   data-min-lat / data-max-lat / data-min-lng / data-max-lng — current
 *     filter bounds (empty string when no bound is set).
 *   data-obs-version — bumped by the LV on every filter-driven obs
 *     reload; used to know when to re-read points from the chart.
 *   data-tiles-url — optional, defaults to /tiles/boundaries.pmtiles
 *     (matches range_map).
 */

import maplibregl from 'maplibre-gl'
import { Protocol } from 'pmtiles'
import { readPoints } from './phenology_state'

const WORLD_BOUNDS = [
  [-180, -65],
  [180, 80],
]

// Match the chart's color scheme (sexgen=blue, agamic=red, unknown=gray)
// so the user reads the map and the chart together without translation.
const GEN_COLOR_EXPR = [
  'match',
  ['get', 'generation'],
  'sexgen', '#1f77b4',
  'agamic', '#d62728',
  '#555555',
]

let protocolRegistered = false
function ensureProtocol() {
  if (!protocolRegistered) {
    const protocol = new Protocol()
    maplibregl.addProtocol('pmtiles', protocol.tile)
    protocolRegistered = true
  }
}

export default {
  mounted() {
    ensureProtocol()
    this.tilesUrl = this.el.dataset.tilesUrl || '/tiles/boundaries.pmtiles'
    this._drawing = false
    this._dragStart = null
    this._lastObsVersion = ''
    this._initMap()

    // The map may be mounted inside the collapsed (display:none) advanced
    // filter panel, where MapLibre sizes its canvas to 0. When the panel is
    // expanded the LiveView pushes this event so we can pick up the real size.
    this.handleEvent('phenology:filters-shown', () => {
      if (this.map) this.map.resize()
    })
  },

  updated() {
    if (!this.map) return
    if (!this._mapReady) {
      // Box / obs sync will be done from the 'load' handler once layers
      // are added — bail until then.
      return
    }
    this._syncBoxFromAttrs()
    this._syncTargetLat()
    if (this.el.dataset.obsVersion !== this._lastObsVersion) {
      this._lastObsVersion = this.el.dataset.obsVersion || ''
      this._syncObs()
    }
  },

  // -------------------------------------------------------------------
  // Target-latitude reference line (shown in prediction mode)
  // -------------------------------------------------------------------

  _syncTargetLat() {
    const src = this.map.getSource('target-lat')
    if (!src) return

    const shown = this.el.dataset.targetLatShown === 'true'
    const lat = parseFloat(this.el.dataset.targetLat)

    if (!shown || Number.isNaN(lat)) {
      src.setData(emptyFeatureCollection())
      return
    }

    src.setData({
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          properties: {},
          geometry: {
            type: 'LineString',
            coordinates: [[-180, lat], [-90, lat], [0, lat], [90, lat], [180, lat]],
          },
        },
      ],
    })
  },

  destroyed() {
    if (this._windowMouseUp) {
      window.removeEventListener('mouseup', this._windowMouseUp)
      this._windowMouseUp = null
    }
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  },

  // -------------------------------------------------------------------
  // Setup
  // -------------------------------------------------------------------

  _initMap() {
    this.map = new maplibregl.Map({
      container: this.el,
      boxZoom: false,
      style: {
        version: 8,
        sources: {
          boundaries: { type: 'vector', url: `pmtiles://${this.tilesUrl}` },
          'user-bbox': { type: 'geojson', data: emptyFeatureCollection() },
          obs: { type: 'geojson', data: emptyFeatureCollection() },
          'target-lat': { type: 'geojson', data: emptyFeatureCollection() },
        },
        layers: [
          { id: 'background', type: 'background', paint: { 'background-color': '#ADD8E6' } },
          {
            id: 'countries-fill',
            type: 'fill',
            source: 'boundaries',
            'source-layer': 'countries',
            paint: { 'fill-color': '#F5F3EC' },
          },
          {
            id: 'subdivisions-line',
            type: 'line',
            source: 'boundaries',
            'source-layer': 'subdivisions',
            paint: {
              'line-color': '#bbb',
              'line-width': [
                'interpolate', ['linear'], ['zoom'],
                2, 0.1, 5, 0.3, 8, 0.6,
              ],
            },
          },
          {
            id: 'countries-line',
            type: 'line',
            source: 'boundaries',
            'source-layer': 'countries',
            paint: {
              'line-color': '#666',
              'line-width': [
                'interpolate', ['linear'], ['zoom'],
                2, 0.8, 6, 1.2,
              ],
            },
          },
          {
            id: 'lakes-fill',
            type: 'fill',
            source: 'boundaries',
            'source-layer': 'lakes',
            paint: { 'fill-color': '#ADD8E6' },
          },
          {
            id: 'obs-points',
            type: 'circle',
            source: 'obs',
            paint: {
              'circle-radius': [
                'interpolate', ['linear'], ['zoom'],
                2, 2, 6, 3.5, 10, 5,
              ],
              'circle-color': GEN_COLOR_EXPR,
              'circle-opacity': 0.6,
              'circle-stroke-width': 0.4,
              'circle-stroke-color': '#222',
            },
          },
          {
            id: 'user-bbox-fill',
            type: 'fill',
            source: 'user-bbox',
            paint: {
              'fill-color': '#2b5e3a',
              'fill-opacity': 0.15,
            },
          },
          {
            id: 'user-bbox-line',
            type: 'line',
            source: 'user-bbox',
            paint: {
              'line-color': '#2b5e3a',
              'line-width': 2,
            },
          },
          {
            id: 'target-lat-line',
            type: 'line',
            source: 'target-lat',
            paint: {
              'line-color': '#661419',
              'line-width': 1.5,
              'line-dasharray': [3, 2],
            },
          },
        ],
      },
      center: [0, 20],
      zoom: 1,
      minZoom: 0,
      attributionControl: false,
    })

    this.map.addControl(
      new maplibregl.AttributionControl({
        compact: true,
        customAttribution: 'Natural Earth',
      }),
    )
    this.map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right')

    this.map.fitBounds(WORLD_BOUNDS, { padding: 10, animate: false })

    this.map.on('load', () => {
      this._mapReady = true
      this._lastObsVersion = this.el.dataset.obsVersion || ''
      this._syncObs()
      this._syncBoxFromAttrs()
      this._syncTargetLat()
      this._wireDrawing()
    })
  },

  // -------------------------------------------------------------------
  // Shift+drag to draw the bounding box
  // -------------------------------------------------------------------

  _wireDrawing() {
    const map = this.map
    const canvas = map.getCanvas()

    map.on('mousedown', (e) => {
      if (!e.originalEvent.shiftKey) return
      this._drawing = true
      this._dragStart = e.lngLat
      map.dragPan.disable()
      canvas.style.cursor = 'crosshair'
      this._setBox(e.lngLat, e.lngLat)
      e.preventDefault()
    })

    map.on('mousemove', (e) => {
      if (!this._drawing) return
      this._setBox(this._dragStart, e.lngLat)
    })

    const finishDraw = (lngLat) => {
      if (!this._drawing) return
      this._drawing = false
      map.dragPan.enable()
      canvas.style.cursor = ''
      const a = this._dragStart
      const b = lngLat || a
      this._dragStart = null

      const minLat = Math.min(a.lat, b.lat)
      const maxLat = Math.max(a.lat, b.lat)
      const minLng = Math.min(a.lng, b.lng)
      const maxLng = Math.max(a.lng, b.lng)

      // Ignore accidental shift-clicks — too tiny to mean anything.
      if (Math.abs(maxLat - minLat) < 0.01 || Math.abs(maxLng - minLng) < 0.01) {
        this._syncBoxFromAttrs()
        return
      }

      this._writeInputs({ min_lat: minLat, max_lat: maxLat, min_lng: minLng, max_lng: maxLng })
    }

    map.on('mouseup', (e) => finishDraw(e.lngLat))

    // mouseup outside the canvas (user released past the map edge): fall
    // back to whatever lngLat we last saw via mousemove. Without this,
    // the box never finalizes if the cursor leaves the map.
    this._windowMouseUp = () => finishDraw(null)
    window.addEventListener('mouseup', this._windowMouseUp)
  },

  // -------------------------------------------------------------------
  // Sync helpers
  // -------------------------------------------------------------------

  // Render the bounding-box GeoJSON for the given corner lngLats. Used
  // both during the live drag and for hydrating from form-input state.
  _setBox(a, b) {
    if (!this.map || !this.map.getSource('user-bbox')) return
    if (!a || !b) {
      this.map.getSource('user-bbox').setData(emptyFeatureCollection())
      return
    }
    const minLat = Math.min(a.lat, b.lat)
    const maxLat = Math.max(a.lat, b.lat)
    const minLng = Math.min(a.lng, b.lng)
    const maxLng = Math.max(a.lng, b.lng)
    this.map.getSource('user-bbox').setData({
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          properties: {},
          geometry: {
            type: 'Polygon',
            coordinates: [[
              [minLng, minLat],
              [maxLng, minLat],
              [maxLng, maxLat],
              [minLng, maxLat],
              [minLng, minLat],
            ]],
          },
        },
      ],
    })
  },

  _syncBoxFromAttrs() {
    if (this._drawing) return
    const minLat = parseFloatOrNull(this.el.dataset.minLat)
    const maxLat = parseFloatOrNull(this.el.dataset.maxLat)
    const minLng = parseFloatOrNull(this.el.dataset.minLng)
    const maxLng = parseFloatOrNull(this.el.dataset.maxLng)

    // A valid filter rectangle needs all four bounds. If only some are
    // set the SQL still filters with partial bounds, but we can't draw
    // a rectangle without all four corners — so just clear the visual.
    if (minLat == null || maxLat == null || minLng == null || maxLng == null) {
      this._setBox(null, null)
      return
    }
    this._setBox({ lat: minLat, lng: minLng }, { lat: maxLat, lng: maxLng })
  },

  _syncObs() {
    if (!this.map || !this.map.getSource('obs')) return
    const points = readPoints()
    const features = points
      .filter((p) => typeof p.lat === 'number' && typeof p.lng === 'number')
      .map((p) => ({
        type: 'Feature',
        properties: { generation: p.generation || 'unknown' },
        geometry: { type: 'Point', coordinates: [p.lng, p.lat] },
      }))
    this.map.getSource('obs').setData({ type: 'FeatureCollection', features })
  },

  // -------------------------------------------------------------------
  // Form sync
  // -------------------------------------------------------------------

  _writeInputs(bounds) {
    for (const [name, value] of Object.entries(bounds)) {
      const el = document.querySelector(`input[name="${name}"]`)
      if (!el) continue
      el.value = value.toFixed(4)
      // Phoenix LV's form-level phx-change listens for input/change
      // events from descendants. Dispatch both for safety: phx-debounce
      // pipelines on input, but some setups use change.
      el.dispatchEvent(new Event('input', { bubbles: true }))
      el.dispatchEvent(new Event('change', { bubbles: true }))
    }
  },
}

function emptyFeatureCollection() {
  return { type: 'FeatureCollection', features: [] }
}

function parseFloatOrNull(s) {
  if (s == null || s === '') return null
  const v = parseFloat(s)
  return Number.isFinite(v) ? v : null
}
