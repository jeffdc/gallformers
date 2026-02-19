/**
 * RangeMap LiveView Hook — MapLibre GL JS + PMTiles
 *
 * Displays a choropleth map of admin-level boundaries (states/provinces).
 * Uses MapLibre GL for WebGL rendering with subdivision-level fills at all
 * zoom levels. Country boundaries are drawn as borders only.
 *
 * Regions are colored:
 *   - Green: in range (exact)
 *   - Light green: inherited range (country/continent-level, not state-confirmed)
 *   - Light red: excluded from range (admin mode only)
 *   - White: not in range
 *
 * Data attributes:
 *   data-in-range:        JSON array of ISO 3166-2 codes in range (e.g., ["US-CA", "US-TX"])
 *   data-excluded-range:  JSON array of ISO 3166-2 codes excluded (optional)
 *   data-inherited-range: JSON array of codes with country/continent-level range (optional)
 *   data-editable:        "true" if regions are clickable (admin mode)
 *   data-tiles-url:       URL to boundaries.pmtiles (default: /data/boundaries.pmtiles)
 *
 * PMTiles feature properties used:
 *   subdivisions: code (ISO 3166-2), name, iso_a2 (country code)
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
  inRange: '#228B22',       // ForestGreen — exact range
  inheritedRange: '#90EE90', // LightGreen — country/continent-level range
  excluded: '#FCA5A5',      // Light red
  default: '#FFFFFF',       // White — not in range
  stroke: '#333333',        // Dark gray border
  countryStroke: '#666666',
  land: '#F3F4F6'           // Gray-100 — base land color for country fills
}

// Default bounds: Western Hemisphere
const HEMISPHERE_BOUNDS = [[-170, -56], [-30, 72]]

/**
 * Build a MapLibre case expression for subdivision choropleth coloring.
 *
 *   1. Check ISO 3166-2 code in range → green
 *   2. Check code inherited → light green
 *   3. Check code excluded → light red (admin only)
 *   4. Fallback → white (not in range)
 */
function buildSubdivisionFillExpression(inRange, excludedRange, inheritedRange, editable) {
  // Helper: build a match expression, or return literal false if the set is empty
  // (MapLibre match requires at least one label-output pair before the fallback)
  function codeMatch(codes) {
    if (codes.size === 0) return false
    const expr = ['match', ['get', 'code']]
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

  // Inherited codes minus any exact (exact takes priority) and minus excluded
  const effectiveInherited = new Set()
  for (const code of inheritedRange) {
    if (!inRange.has(code) && !excludedRange.has(code)) effectiveInherited.add(code)
  }

  const inRangeMatch = codeMatch(effectiveInRange)
  const inheritedMatch = codeMatch(effectiveInherited)

  // Build the case expression, omitting conditions for empty sets
  const expr = ['case']

  if (inRangeMatch !== false) {
    expr.push(inRangeMatch, COLORS.inRange)
  }

  if (inheritedMatch !== false) {
    expr.push(inheritedMatch, COLORS.inheritedRange)
  }

  if (editable) {
    const excludedMatch = codeMatch(excludedRange)
    if (excludedMatch !== false) {
      expr.push(excludedMatch, COLORS.excluded)
    }
  }

  expr.push(COLORS.default)

  return expr
}

const RangeMap = {
  mounted() {
    ensureProtocol()

    this.inRange = new Set(JSON.parse(this.el.dataset.inRange || '[]'))
    this.excludedRange = new Set(JSON.parse(this.el.dataset.excludedRange || '[]'))
    this.inheritedRange = new Set(JSON.parse(this.el.dataset.inheritedRange || '[]'))
    this.editable = this.el.dataset.editable === 'true'
    this.tilesUrl = this.el.dataset.tilesUrl || '/data/boundaries.pmtiles'

    // Listen for range updates from the server (used by gall_host_live)
    this.handleEvent('range-update', ({ in_range, excluded_range, inherited_range }) => {
      this.inRange = new Set(in_range || [])
      this.excludedRange = new Set(excluded_range || [])
      this.inheritedRange = new Set(inherited_range || [])
      this.updateChoropleth()
      this.fitToRange(true)
    })

    // Listen for zoom-to-country events (admin drill-down)
    this.handleEvent('zoom-to-country', ({ code }) => {
      if (!this.map) return
      const features = this.map.querySourceFeatures('boundaries', {
        sourceLayer: 'countries',
        filter: ['==', ['get', 'code'], code]
      })
      if (features.length > 0) {
        const bounds = new maplibregl.LngLatBounds()
        for (const feature of features) {
          forEachCoord(feature.geometry, (lng, lat) => {
            bounds.extend([lng, lat])
          })
        }
        this.map.fitBounds(bounds, { padding: 50, animate: true })
      }
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
    const newInheritedRange = new Set(JSON.parse(this.el.dataset.inheritedRange || '[]'))
    const newEditable = this.el.dataset.editable === 'true'

    // Only update if something actually changed
    if (!setsEqual(newInRange, this.inRange) ||
        !setsEqual(newExcludedRange, this.excludedRange) ||
        !setsEqual(newInheritedRange, this.inheritedRange) ||
        newEditable !== this.editable) {
      this.inRange = newInRange
      this.excludedRange = newExcludedRange
      this.inheritedRange = newInheritedRange
      this.editable = newEditable
      this.updateChoropleth()
      this.fitToRange(true)
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
                this.inRange, this.excludedRange, this.inheritedRange, this.editable
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
      // fitBounds below overrides center/zoom
      center: [-96, 48],
      zoom: 3,
      minZoom: 1,
      maxBounds: [[-180, -60], [0, 85]],
      attributionControl: false
    })

    // Default to hemisphere view; fitToRange will narrow once tiles load
    this.map.fitBounds(HEMISPHERE_BOUNDS, { padding: 20, animate: false })

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

    // Add fullscreen control with escape hint
    this.map.addControl(new maplibregl.FullscreenControl(), 'top-right')

    container.addEventListener('fullscreenchange', () => {
      if (document.fullscreenElement === container) {
        const hint = document.createElement('div')
        hint.className = 'range-map-fullscreen-hint'
        hint.textContent = 'Press Esc to exit fullscreen'
        hint.style.cssText =
          'position:fixed;top:16px;left:50%;transform:translateX(-50%);' +
          'background:rgba(0,0,0,0.7);color:#fff;padding:8px 16px;border-radius:6px;' +
          'font-size:14px;z-index:9999;pointer-events:none;' +
          'transition:opacity 0.5s ease;opacity:1;'
        container.appendChild(hint)
        setTimeout(() => { hint.style.opacity = '0' }, 2000)
        setTimeout(() => { hint.remove() }, 2500)
      }
    })

    // Popup for hover tooltips
    this.popup = new maplibregl.Popup({
      closeButton: false,
      closeOnClick: false,
      offset: 10
    })

    this.map.on('load', () => {
      this.setupInteractions()
      this.fitToRange(false)
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
      const code = feature.properties.code || ''

      let status = ''
      if (this.inRange.has(code) && !this.excludedRange.has(code)) {
        status = ' — Host confirmed'
      } else if (this.inheritedRange.has(code) && !this.excludedRange.has(code)) {
        status = ' — Reported at country level (state not confirmed)'
      } else if (this.editable && this.excludedRange.has(code)) {
        status = ' — Excluded'
      } else {
        status = ' — Not reported'
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

    // Hover: show tooltip on countries (admin mode — shift+click hint)
    map.on('mousemove', 'countries-fill', (e) => {
      if (!this.editable || !e.features || e.features.length === 0) return

      map.getCanvas().style.cursor = 'pointer'

      const feature = e.features[0]
      const name = feature.properties.name || ''

      this.popup
        .setLngLat(e.lngLat)
        .setHTML(`<strong>${name}</strong> — Click to browse states · Shift+click to select all`)
        .addTo(map)
    })

    map.on('mouseleave', 'countries-fill', () => {
      if (!this.editable) return
      map.getCanvas().style.cursor = ''
      this.popup.remove()
    })

    // Click on subdivisions: toggle region (admin) or no-op (public)
    map.on('click', 'subdivisions-fill', (e) => {
      if (!e.features || e.features.length === 0) return

      if (this.editable) {
        const code = e.features[0].properties.code
        if (code) {
          this.pushEvent('toggle_region', { code })
        }
      }
    })

    // Click on countries: drill-in or shift+click to select (admin only)
    map.on('click', 'countries-fill', (e) => {
      if (!this.editable || !e.features || e.features.length === 0) return

      const code = e.features[0].properties.code
      if (!code) return

      if (e.originalEvent.shiftKey) {
        // Shift+click: select/deselect entire country at country precision
        this.pushEvent('toggle_country', { code })
      } else {
        // Regular click: drill into country subdivisions
        this.pushEvent('drill_into_country', { code })
      }
    })
  },

  updateChoropleth() {
    if (!this.map || !this.map.isStyleLoaded()) return

    this.map.setPaintProperty(
      'subdivisions-fill',
      'fill-color',
      buildSubdivisionFillExpression(
        this.inRange, this.excludedRange, this.inheritedRange, this.editable
      )
    )
  },

  /**
   * Fit the map viewport to the bounding box of in-range subdivisions.
   * Falls back to the full hemisphere when there's no range data.
   *
   * Uses querySourceFeatures to get geometries from loaded vector tiles.
   * The map must be at a zoom level where subdivision features are available.
   */
  fitToRange(animate) {
    if (!this.map || !this.map.isStyleLoaded()) return
    if (this.inRange.size === 0 && this.inheritedRange.size === 0) {
      this.map.fitBounds(HEMISPHERE_BOUNDS, { padding: 20, animate })
      return
    }

    const features = this.map.querySourceFeatures('boundaries', {
      sourceLayer: 'subdivisions'
    })

    // Compute bounding box from features matching inRange or inheritedRange codes
    let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity
    let matched = 0

    for (const feature of features) {
      const code = feature.properties.code
      if (!this.inRange.has(code) && !this.inheritedRange.has(code)) continue
      matched++
      forEachCoord(feature.geometry, (lng, lat) => {
        if (lng < minLng) minLng = lng
        if (lng > maxLng) maxLng = lng
        if (lat < minLat) minLat = lat
        if (lat > maxLat) maxLat = lat
      })
    }

    if (matched === 0) {
      // Tiles may not be loaded yet — fall back to hemisphere
      this.map.fitBounds(HEMISPHERE_BOUNDS, { padding: 20, animate })
      return
    }

    this.map.fitBounds([[minLng, minLat], [maxLng, maxLat]], {
      padding: 40,
      maxZoom: 8,
      animate
    })
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

/**
 * Iterate over all coordinates in a GeoJSON geometry, calling fn(lng, lat).
 * Handles Point, MultiPoint, LineString, MultiLineString, Polygon, MultiPolygon.
 */
function forEachCoord(geometry, fn) {
  if (!geometry || !geometry.coordinates) return

  switch (geometry.type) {
    case 'Point':
      fn(geometry.coordinates[0], geometry.coordinates[1])
      break
    case 'MultiPoint':
    case 'LineString':
      for (const coord of geometry.coordinates) fn(coord[0], coord[1])
      break
    case 'MultiLineString':
    case 'Polygon':
      for (const ring of geometry.coordinates) {
        for (const coord of ring) fn(coord[0], coord[1])
      }
      break
    case 'MultiPolygon':
      for (const polygon of geometry.coordinates) {
        for (const ring of polygon) {
          for (const coord of ring) fn(coord[0], coord[1])
        }
      }
      break
  }
}

export default RangeMap
