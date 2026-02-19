/**
 * RangeMap LiveView Hook — MapLibre GL JS + PMTiles
 *
 * Displays a choropleth map of admin-level boundaries (states/provinces).
 * Uses MapLibre GL for WebGL rendering with subdivision-level fills at all
 * zoom levels. Country boundaries are drawn as borders only.
 *
 * Regions are colored:
 *   - Green: in range
 *   - Light red: excluded from range (admin mode only)
 *   - White: not in range, but in a country with data
 *   - Light gray: no data for this country yet
 *
 * Data attributes:
 *   data-in-range:       JSON array of postal codes in range (e.g., ["CA", "TX"])
 *   data-excluded-range: JSON array of postal codes excluded (optional)
 *   data-editable:       "true" if regions are clickable (admin mode)
 *   data-tiles-url:      URL to boundaries.pmtiles (default: /data/boundaries.pmtiles)
 *
 * PMTiles feature properties used:
 *   subdivisions: postal (2-letter postal code), name, iso_a2 (country code)
 *   countries: code (ISO alpha-2), name
 */

import maplibregl from 'maplibre-gl'
import { Protocol } from 'pmtiles'

// Register PMTiles protocol once globally
let protocolRegistered = false
function ensureProtocol() {
  if (!protocolRegistered) {
    const protocol = new Protocol()
    maplibregl.addProtocol('pmtiles', protocol.tile)
    protocolRegistered = true
  }
}

// Color scheme
const COLORS = {
  inRange: '#228B22',       // ForestGreen
  excluded: '#FCA5A5',      // Light red
  default: '#FFFFFF',       // White — country has data but region not in range
  noData: '#E5E7EB',        // Gray-200 — country has no data yet
  stroke: '#333333',        // Dark gray border
  countryStroke: '#666666',
  land: '#F3F4F6'           // Gray-100 — base land color for country fills
}

// Countries we currently have range data for. Expand this list as
// Western Hemisphere expansion (matter 1db6) progresses.
const COUNTRIES_WITH_DATA = new Set(['US', 'CA'])

// Default bounds: US + Canada (sw corner to ne corner)
const US_CANADA_BOUNDS = [[-136, 24], [-52, 72]]

/**
 * Build a MapLibre case expression for subdivision choropleth coloring.
 *
 * Uses a layered case expression with country gating to prevent postal code
 * collisions across countries (e.g., "MI" = Michigan AND Michoacán):
 *   1. Check postal code in range AND country has data → green
 *   2. Check postal code excluded AND country has data → light red (admin only)
 *   3. Check country has data → white (not in range)
 *   4. Fallback → light gray (no data for this country)
 */
function buildSubdivisionFillExpression(inRange, excludedRange, editable) {
  // Helper: build a match expression, or return literal false if the set is empty
  // (MapLibre match requires at least one label-output pair before the fallback)
  function postalMatch(codes) {
    if (codes.size === 0) return false
    const expr = ['match', ['get', 'postal']]
    for (const code of codes) {
      expr.push(code, true)
    }
    expr.push(false)
    return expr
  }

  // Codes in range minus any excluded
  const effectiveInRange = new Set()
  for (const code of inRange) {
    if (!excludedRange.has(code)) effectiveInRange.add(code)
  }

  const inRangeMatch = postalMatch(effectiveInRange)

  // Gate: feature must be in a country we have data for
  const countryMatch = ['match', ['get', 'iso_a2']]
  for (const cc of COUNTRIES_WITH_DATA) {
    countryMatch.push(cc, true)
  }
  countryMatch.push(false)

  // Build the case expression, omitting conditions for empty sets
  const expr = ['case']

  if (inRangeMatch !== false) {
    expr.push(['all', inRangeMatch, countryMatch], COLORS.inRange)
  }

  if (editable) {
    const excludedMatch = postalMatch(excludedRange)
    if (excludedMatch !== false) {
      expr.push(['all', excludedMatch, countryMatch], COLORS.excluded)
    }
  }

  expr.push(countryMatch, COLORS.default)
  expr.push(COLORS.noData)

  return expr
}

const RangeMap = {
  mounted() {
    ensureProtocol()

    this.inRange = new Set(JSON.parse(this.el.dataset.inRange || '[]'))
    this.excludedRange = new Set(JSON.parse(this.el.dataset.excludedRange || '[]'))
    this.editable = this.el.dataset.editable === 'true'
    this.tilesUrl = this.el.dataset.tilesUrl || '/data/boundaries.pmtiles'

    // Listen for range updates from the server (used by gall_host_live)
    this.handleEvent('range-update', ({ in_range, excluded_range }) => {
      this.inRange = new Set(in_range || [])
      this.excludedRange = new Set(excluded_range || [])
      this.updateChoropleth()
    })

    this.initMap()
  },

  // Called when LiveView re-renders — re-read data attributes.
  // With phx-update="ignore", the DOM children aren't patched but attributes
  // may be updated and the hook callback still fires. This is how the admin
  // host form communicates select_all / deselect_all / toggle_region changes.
  updated() {
    const newInRange = new Set(JSON.parse(this.el.dataset.inRange || '[]'))
    const newExcludedRange = new Set(JSON.parse(this.el.dataset.excludedRange || '[]'))
    const newEditable = this.el.dataset.editable === 'true'

    // Only update if something actually changed
    if (!setsEqual(newInRange, this.inRange) ||
        !setsEqual(newExcludedRange, this.excludedRange) ||
        newEditable !== this.editable) {
      this.inRange = newInRange
      this.excludedRange = newExcludedRange
      this.editable = newEditable
      this.updateChoropleth()
    }
  },

  destroyed() {
    if (this.map) {
      this.map.remove()
      this.map = null
    }
  },

  initMap() {
    const container = this.el

    this.map = new maplibregl.Map({
      container,
      style: {
        version: 8,
        sources: {
          boundaries: {
            type: 'vector',
            url: `pmtiles://${this.tilesUrl}`
          }
        },
        layers: [
          // Ocean background
          {
            id: 'background',
            type: 'background',
            paint: { 'background-color': '#ADD8E6' }
          },
          // Country fills — neutral land color (not range-based)
          {
            id: 'countries-fill',
            type: 'fill',
            source: 'boundaries',
            'source-layer': 'countries',
            paint: {
              'fill-color': COLORS.land
            }
          },
          // Subdivision fills — range-based choropleth at all zoom levels
          {
            id: 'subdivisions-fill',
            type: 'fill',
            source: 'boundaries',
            'source-layer': 'subdivisions',
            paint: {
              'fill-color': buildSubdivisionFillExpression(
                this.inRange, this.excludedRange, this.editable
              ),
              'fill-opacity': 1
            }
          },
          // Subdivision borders
          {
            id: 'subdivisions-line',
            type: 'line',
            source: 'boundaries',
            'source-layer': 'subdivisions',
            paint: {
              'line-color': COLORS.stroke,
              'line-width': [
                'interpolate', ['linear'], ['zoom'],
                2, 0.15,
                5, 0.4,
                8, 0.8
              ]
            }
          },
          // Country borders — drawn on top of subdivisions
          {
            id: 'countries-line',
            type: 'line',
            source: 'boundaries',
            'source-layer': 'countries',
            paint: {
              'line-color': COLORS.countryStroke,
              'line-width': [
                'interpolate', ['linear'], ['zoom'],
                2, 0.8,
                6, 1.5
              ]
            }
          },
          // Lakes overlay
          {
            id: 'lakes-fill',
            type: 'fill',
            source: 'boundaries',
            'source-layer': 'lakes',
            paint: {
              'fill-color': '#ADD8E6'
            }
          },
          {
            id: 'lakes-line',
            type: 'line',
            source: 'boundaries',
            'source-layer': 'lakes',
            paint: {
              'line-color': '#4682B4',
              'line-width': 0.5
            }
          }
        ]
      },
      // Fit US+Canada on load; fitBounds below overrides center/zoom
      center: [-96, 48],
      zoom: 3,
      minZoom: 2,
      maxBounds: [[-180, -60], [0, 85]],
      attributionControl: false
    })

    // Fit to US+Canada bounds on initial load
    this.map.fitBounds(US_CANADA_BOUNDS, { padding: 20, animate: false })

    // Add minimal attribution
    this.map.addControl(new maplibregl.AttributionControl({
      compact: true,
      customAttribution: 'Natural Earth'
    }))

    // Add zoom controls
    this.map.addControl(
      new maplibregl.NavigationControl({ showCompass: false }),
      'top-right'
    )

    // Add fullscreen control
    this.map.addControl(new maplibregl.FullscreenControl(), 'top-right')

    // Popup for hover tooltips
    this.popup = new maplibregl.Popup({
      closeButton: false,
      closeOnClick: false,
      offset: 10
    })

    this.map.on('load', () => {
      this.setupInteractions()
    })
  },

  setupInteractions() {
    const map = this.map

    // Hover: show tooltip on subdivisions
    map.on('mousemove', 'subdivisions-fill', (e) => {
      if (!e.features || e.features.length === 0) return

      map.getCanvas().style.cursor = this.editable ? 'pointer' : 'default'

      const feature = e.features[0]
      const name = feature.properties.name || ''
      const code = feature.properties.postal || ''
      const country = feature.properties.iso_a2 || ''

      let status = ''
      if (this.inRange.has(code) && !this.excludedRange.has(code)) {
        status = ' — in range'
      } else if (this.excludedRange.has(code)) {
        status = ' — excluded'
      } else if (!COUNTRIES_WITH_DATA.has(country)) {
        status = ' — no data yet'
      }

      this.popup
        .setLngLat(e.lngLat)
        .setHTML(`<strong>${name}</strong> (${code})${status}`)
        .addTo(map)
    })

    map.on('mouseleave', 'subdivisions-fill', () => {
      map.getCanvas().style.cursor = ''
      this.popup.remove()
    })

    // Click on subdivisions: toggle region (admin) or no-op (public)
    map.on('click', 'subdivisions-fill', (e) => {
      if (!e.features || e.features.length === 0) return

      if (this.editable) {
        const code = e.features[0].properties.postal
        if (code) {
          this.pushEvent('toggle_region', { code })
        }
      }
    })
  },

  updateChoropleth() {
    if (!this.map || !this.map.isStyleLoaded()) return

    this.map.setPaintProperty(
      'subdivisions-fill',
      'fill-color',
      buildSubdivisionFillExpression(this.inRange, this.excludedRange, this.editable)
    )
  }
}

/**
 * Compare two Sets for equality.
 */
function setsEqual(a, b) {
  if (a.size !== b.size) return false
  for (const v of a) {
    if (!b.has(v)) return false
  }
  return true
}

export default RangeMap
