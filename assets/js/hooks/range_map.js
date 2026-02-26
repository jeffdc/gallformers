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
 *   data-navigable:       "true" if clicking a region navigates to its place page
 *   data-tiles-url:       URL to boundaries.pmtiles (default: /data/boundaries.pmtiles)
 *   data-empty-text:      Text shown when no range data exists (default: "No range data available")
 *   data-max-bounds:      JSON [[west, south], [east, north]] max bounds (optional)
 *   data-bounds:          JSON [[west, south], [east, north]] server-provided initial bounds (optional)
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
  land: '#F3F4F6',          // Gray-100 — base land color for country fills
  // Place mode: geographic presence (not host data)
  placeHighlight: '#3B82F6', // Blue-500 — place membership
  placeHighlightLight: '#93C5FD' // Blue-300 — lighter variant
}

// Default bounds: global view (excludes Antarctica)
const WORLD_BOUNDS = [[-180, -58], [180, 84]]

/**
 * Compute effective in-range and inherited sets by subtracting exclusions.
 * Returns { effectiveInRange, effectiveInherited } as Sets.
 */
function computeEffectiveSets(inRange, excludedRange, inheritedRange) {
  const effectiveInRange = new Set()
  for (const code of inRange) {
    if (!excludedRange.has(code)) effectiveInRange.add(code)
  }

  const effectiveInherited = new Set()
  for (const code of inheritedRange) {
    if (!inRange.has(code) && !excludedRange.has(code)) effectiveInherited.add(code)
  }

  return { effectiveInRange, effectiveInherited }
}

/**
 * Build a MapLibre case expression for choropleth coloring.
 * Accepts pre-computed effective sets from computeEffectiveSets().
 *
 *   1. Check code in effective range → green
 *   2. Check code in effective inherited → light green
 *   3. Check code excluded → light red (admin only)
 *   4. Fallback → fallbackColor
 */
function buildFillExpression(effectiveInRange, effectiveInherited, excludedRange, editable, fallbackColor, colorOverrides) {
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

  const inRangeMatch = codeMatch(effectiveInRange)
  const inheritedMatch = codeMatch(effectiveInherited)

  const inRangeColor = (colorOverrides && colorOverrides.inRange) || COLORS.inRange
  const inheritedColor = (colorOverrides && colorOverrides.inheritedRange) || COLORS.inheritedRange

  // Build the case expression, omitting conditions for empty sets
  const expr = ['case']

  if (inRangeMatch !== false) {
    expr.push(inRangeMatch, inRangeColor)
  }

  if (inheritedMatch !== false) {
    expr.push(inheritedMatch, inheritedColor)
  }

  if (editable) {
    const excludedMatch = codeMatch(excludedRange)
    if (excludedMatch !== false) {
      expr.push(excludedMatch, COLORS.excluded)
    }
  }

  expr.push(fallbackColor)

  // A case expression with no conditions (only the fallback) is invalid
  // in MapLibre. Return the fallback color as a literal instead.
  if (expr.length === 2) return fallbackColor

  return expr
}

const RangeMap = {
  mounted() {
    ensureProtocol()

    this.inRange = new Set(JSON.parse(this.el.dataset.inRange || '[]'))
    this.excludedRange = new Set(JSON.parse(this.el.dataset.excludedRange || '[]'))
    this.inheritedRange = new Set(JSON.parse(this.el.dataset.inheritedRange || '[]'))
    this.editable = this.el.dataset.editable === 'true'
    this.navigable = this.el.dataset.navigable === 'true'
    this.placeMode = this.el.dataset.placeMode === 'true'
    this.tilesUrl = this.el.dataset.tilesUrl || '/data/boundaries.pmtiles'
    this.emptyText = this.el.dataset.emptyText || 'No range data available'

    const maxBoundsAttr = this.el.dataset.maxBounds
    this.maxBounds = maxBoundsAttr ? JSON.parse(maxBoundsAttr) : undefined

    this.colorOverrides = this.placeMode
      ? { inRange: COLORS.placeHighlight, inheritedRange: COLORS.placeHighlightLight }
      : null

    // Listen for range updates from the server (used by gall_host_live)
    this.handleEvent('range-update', ({ in_range, excluded_range, inherited_range }) => {
      this.inRange = new Set(in_range || [])
      this.excludedRange = new Set(excluded_range || [])
      this.inheritedRange = new Set(inherited_range || [])
      this.updateChoropleth()
      this.fitToRange(true)
    })

    // Drill-down zoom events from CountryDrillDown / ExclusionDrillDown panel
    this.drillDownCountry = null
    this.handleEvent('range-zoom-to-country', ({ code }) => {
      this.drillDownCountry = code
      this.zoomToCountry(code)
    })

    this.handleEvent('range-zoom-out', () => {
      this.drillDownCountry = null
      this.fitToRange(true)
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
    const newNavigable = this.el.dataset.navigable === 'true'
    const newPlaceMode = this.el.dataset.placeMode === 'true'

    // Only update if something actually changed
    if (!setsEqual(newInRange, this.inRange) ||
        !setsEqual(newExcludedRange, this.excludedRange) ||
        !setsEqual(newInheritedRange, this.inheritedRange) ||
        newEditable !== this.editable ||
        newNavigable !== this.navigable ||
        newPlaceMode !== this.placeMode) {
      this.inRange = newInRange
      this.excludedRange = newExcludedRange
      this.inheritedRange = newInheritedRange
      this.editable = newEditable
      this.navigable = newNavigable
      this.placeMode = newPlaceMode
      this.colorOverrides = this.placeMode
        ? { inRange: COLORS.placeHighlight, inheritedRange: COLORS.placeHighlightLight }
        : null
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

    const { effectiveInRange, effectiveInherited } = computeEffectiveSets(
      this.inRange, this.excludedRange, this.inheritedRange
    )

    this.map = new maplibregl.Map({
      container,
      boxZoom: false,
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
          // Country fills — range-based for leaf countries (territories),
          // neutral land color fallback for countries with subdivisions
          {
            id: 'countries-fill',
            type: 'fill',
            source: 'boundaries',
            'source-layer': 'countries',
            paint: {
              'fill-color': buildFillExpression(
                effectiveInRange, effectiveInherited, this.excludedRange, this.editable, COLORS.land, this.colorOverrides
              )
            }
          },
          // Subdivision fills — range-based choropleth at all zoom levels.
          // In place mode, use transparent fallback so countries-fill shows through
          // for non-subdivided countries (leaf countries like MP, NR, etc.)
          {
            id: 'subdivisions-fill',
            type: 'fill',
            source: 'boundaries',
            'source-layer': 'subdivisions',
            paint: {
              'fill-color': buildFillExpression(
                effectiveInRange, effectiveInherited, this.excludedRange, this.editable,
                this.placeMode ? 'transparent' : COLORS.default, this.colorOverrides
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
      center: [0, 30],
      zoom: 3,
      minZoom: 1,
      maxBounds: this.maxBounds,
      attributionControl: false
    })

    // Default to world view; fitToRange will narrow once tiles load
    this.map.fitBounds(WORLD_BOUNDS, { padding: 20, animate: false })

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
        hint.textContent = 'Press Esc to exit fullscreen'
        hint.className = 'fixed top-4 left-1/2 -translate-x-1/2 bg-black/70 text-white px-4 py-2 rounded-md text-sm z-[9999] pointer-events-none transition-opacity duration-500'
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

    this.map.on('error', (e) => {
      if (e.error && e.error.message && e.error.message.includes('pmtiles')) {
        const errorDiv = document.createElement('div')
        errorDiv.className = 'absolute inset-0 flex items-center justify-center bg-gray-100'
        errorDiv.innerHTML = '<span class="text-gray-500 text-sm">Map data unavailable</span>'
        this.el.appendChild(errorDiv)
      }
    })

    this.map.on('load', () => {
      this.setupInteractions()
      this.fitToRange(false)
      this.updateEmptyState()
    })
  },

  setupInteractions() {
    const map = this.map

    // Hover: show tooltip on subdivisions
    map.on('mousemove', 'subdivisions-fill', (e) => {
      if (!e.features || e.features.length === 0) return

      map.getCanvas().style.cursor = (this.editable || this.navigable) ? 'pointer' : 'default'

      const feature = e.features[0]
      const name = feature.properties.name || ''
      const code = feature.properties.code || ''

      let status = ''
      if (this.placeMode) {
        // Place detail pages: no range status, just show the name
        status = ''
      } else if (this.inRange.has(code) && !this.excludedRange.has(code)) {
        status = ' — Documented'
      } else if (this.inheritedRange.has(code) && !this.excludedRange.has(code)) {
        status = ' — Country-level record only'
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

    // Hover: show tooltip on countries (leaf territories without subdivisions)
    map.on('mousemove', 'countries-fill', (e) => {
      if (!e.features || e.features.length === 0) return

      // Only show country tooltip when no subdivision is under cursor
      const subdivs = map.queryRenderedFeatures(e.point, { layers: ['subdivisions-fill'] })
      if (subdivs.length > 0) return

      const feature = e.features[0]
      const name = feature.properties.name || ''
      const code = feature.properties.code || ''

      if (this.editable) {
        map.getCanvas().style.cursor = 'pointer'

        let status = ''
        if (this.excludedRange.has(code)) {
          status = ' — Excluded'
        } else if (this.inRange.has(code)) {
          status = ' — Documented'
        } else if (this.inheritedRange.has(code)) {
          status = ' — Country-level record only'
        }

        this.popup
          .setLngLat(e.lngLat)
          .setHTML(`<strong>${name}</strong> (${code})${status} — Click to edit range`)
          .addTo(map)
      } else {
        map.getCanvas().style.cursor = this.navigable ? 'pointer' : 'default'

        let status = ''
        if (this.inRange.has(code)) {
          status = this.placeMode ? '' : ' — Documented'
        } else if (this.inheritedRange.has(code)) {
          status = ' — Country-level record only'
        } else {
          status = this.placeMode ? '' : ' — Not reported'
        }

        this.popup
          .setLngLat(e.lngLat)
          .setHTML(`<strong>${name}</strong> (${code})${status}`)
          .addTo(map)
      }
    })

    map.on('mouseleave', 'countries-fill', () => {
      map.getCanvas().style.cursor = ''
      this.popup.remove()
    })

    // Unified click handler — uses queryRenderedFeatures to resolve layer priority.
    // Without this, both subdivisions-fill and countries-fill handlers fire on
    // the same click (they overlap geographically), causing double events.
    map.on('click', (e) => {
      const subdivs = map.queryRenderedFeatures(e.point, { layers: ['subdivisions-fill'] })
      const countries = map.queryRenderedFeatures(e.point, { layers: ['countries-fill'] })

      // At low zoom, tippecanoe may coalesce subdivision features, producing
      // entries with bare country codes (e.g., "BR") alongside real subdivision
      // codes (e.g., "BR-AM"). Prefer the most specific (hyphenated) code.
      const subdivCode = pickSubdivisionCode(subdivs)
      const countryCode = countries.length > 0 ? countries[0].properties.code : null

      // A bare country code from the subdivisions layer means the features are
      // coalesced at this zoom level — treat as a country click, not subdivision.
      const isRealSubdiv = subdivCode && subdivCode.includes('-')

      if (this.editable) {
        // When zoomed into a country (drill-down open), clicking a subdivision
        // toggles it directly instead of re-opening the drill-down panel.
        if (this.drillDownCountry && isRealSubdiv && subdivCode.startsWith(this.drillDownCountry + '-')) {
          this.pushEvent('toggle_region', { code: subdivCode })
        } else {
          // Determine the country for this click point
          const clickCountry = countryCode || (isRealSubdiv && subdivCode.split('-')[0]) || null

          if (clickCountry) {
            // Open the country drill-down panel (or toggle directly for leaf countries)
            this.pushEvent('toggle_country', { code: clickCountry })
          } else if (isRealSubdiv) {
            // Fallback: subdivision with no country (shouldn't happen normally)
            this.pushEvent('toggle_region', { code: subdivCode })
          }
        }
      } else if (this.navigable) {
        if (isRealSubdiv) {
          this.pushEvent('navigate_to_place', { code: subdivCode })
        } else if (countryCode) {
          this.pushEvent('navigate_to_place', { code: countryCode })
        }
      }
    })
  },

  updateChoropleth() {
    if (!this.map || !this.map.isStyleLoaded()) return

    const { effectiveInRange, effectiveInherited } = computeEffectiveSets(
      this.inRange, this.excludedRange, this.inheritedRange
    )

    this.map.setPaintProperty(
      'countries-fill',
      'fill-color',
      buildFillExpression(
        effectiveInRange, effectiveInherited, this.excludedRange, this.editable, COLORS.land, this.colorOverrides
      )
    )

    this.map.setPaintProperty(
      'subdivisions-fill',
      'fill-color',
      buildFillExpression(
        effectiveInRange, effectiveInherited, this.excludedRange, this.editable,
        this.placeMode ? 'transparent' : COLORS.default, this.colorOverrides
      )
    )

    this.updateEmptyState()
  },

  /**
   * Show or hide an overlay when there is no range data to display.
   */
  updateEmptyState() {
    const hasData = this.inRange.size > 0 || this.inheritedRange.size > 0
    const existing = this.el.querySelector('.range-map-empty-overlay')

    if (hasData && existing) {
      existing.remove()
    } else if (!hasData && !existing) {
      const overlay = document.createElement('div')
      overlay.className = 'range-map-empty-overlay absolute inset-0 flex items-center justify-center bg-gray-100/60 pointer-events-none z-10'
      overlay.innerHTML = `<span class="text-gray-500 text-sm">${this.emptyText}</span>`
      this.el.appendChild(overlay)
    }
  },

  /**
   * Fit the map viewport to the bounding box of in-range subdivisions.
   * Falls back to the full world view when there's no range data.
   *
   * Uses querySourceFeatures to get geometries from loaded vector tiles.
   * The map must be at a zoom level where subdivision features are available.
   */
  fitToRange(animate) {
    if (!this.map || !this.map.isStyleLoaded()) return
    if (this.inRange.size === 0 && this.inheritedRange.size === 0) {
      this.map.fitBounds(WORLD_BOUNDS, { padding: 20, animate })
      return
    }

    // Prefer server-provided bounds when available
    const boundsAttr = this.el.dataset.bounds
    if (boundsAttr) {
      const bounds = JSON.parse(boundsAttr)
      this.map.fitBounds(bounds, { padding: 40, maxZoom: 8, animate })
      return
    }

    // Query both subdivisions and countries layers — leaf countries (territories
    // like Grenada, Puerto Rico) only exist in the countries layer
    const subdivFeatures = this.map.querySourceFeatures('boundaries', {
      sourceLayer: 'subdivisions'
    })
    const countryFeatures = this.map.querySourceFeatures('boundaries', {
      sourceLayer: 'countries'
    })

    // Compute bounding box from features matching inRange or inheritedRange codes
    let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity
    let matched = 0

    const updateBounds = (feature) => {
      forEachCoord(feature.geometry, (lng, lat) => {
        if (lng < minLng) minLng = lng
        if (lng > maxLng) maxLng = lng
        if (lat < minLat) minLat = lat
        if (lat > maxLat) maxLat = lat
      })
    }

    for (const feature of subdivFeatures) {
      const code = feature.properties.code
      if (!this.inRange.has(code) && !this.inheritedRange.has(code)) continue
      matched++
      updateBounds(feature)
    }

    for (const feature of countryFeatures) {
      const code = feature.properties.code
      if (!this.inRange.has(code) && !this.inheritedRange.has(code)) continue
      matched++
      updateBounds(feature)
    }

    if (matched === 0) {
      // Tiles may not be loaded yet — fall back to world view
      this.map.fitBounds(WORLD_BOUNDS, { padding: 20, animate })
      return
    }

    this.map.fitBounds([[minLng, minLat], [maxLng, maxLat]], {
      padding: 40,
      maxZoom: 8,
      animate
    })
  },

  /**
   * Zoom the map to show a specific country and its subdivisions.
   * Used when the drill-down panel opens for a country.
   */
  zoomToCountry(code) {
    if (!this.map || !this.map.isStyleLoaded()) return

    let minLng = Infinity, minLat = Infinity, maxLng = -Infinity, maxLat = -Infinity
    let matched = 0

    const updateBounds = (lng, lat) => {
      if (lng < minLng) minLng = lng
      if (lng > maxLng) maxLng = lng
      if (lat < minLat) minLat = lat
      if (lat > maxLat) maxLat = lat
    }

    // Scan both country and subdivision features in a single pass per layer.
    // Country features match on code; subdivision features match on iso_a2.
    const layers = [
      { sourceLayer: 'countries', matchKey: 'code' },
      { sourceLayer: 'subdivisions', matchKey: 'iso_a2' }
    ]

    for (const { sourceLayer, matchKey } of layers) {
      const features = this.map.querySourceFeatures('boundaries', { sourceLayer })
      for (const feature of features) {
        if (feature.properties[matchKey] !== code) continue
        matched++
        forEachCoord(feature.geometry, updateBounds)
      }
    }

    if (matched > 0) {
      this.map.fitBounds([[minLng, minLat], [maxLng, maxLat]], {
        padding: 40,
        maxZoom: 8,
        animate: true
      })
    }
  }
}

/**
 * Pick the best subdivision code from queryRenderedFeatures results.
 * At low zoom, tippecanoe may coalesce features, producing entries with
 * bare country codes (e.g., "BR") alongside real subdivision codes
 * (e.g., "BR-AM"). Prefer hyphenated (most specific) codes.
 * Returns null if no valid code found.
 */
function pickSubdivisionCode(features) {
  if (features.length === 0) return null
  // Prefer a code containing a hyphen (real subdivision like BR-AM, US-SD)
  for (const f of features) {
    const code = f.properties.code
    if (code && code.includes('-')) return code
  }
  // Fall back to first code (may be a bare country code for leaf territories)
  return features[0].properties.code || null
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
