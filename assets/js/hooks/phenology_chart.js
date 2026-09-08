import { select } from 'd3-selection'
import { scaleLinear } from 'd3-scale'
import { axisBottom, axisLeft } from 'd3-axis'
import { extent } from 'd3-array'
import { brush } from 'd3-brush'
import { symbol, symbolCircle, symbolTriangle, symbolSquare,
         symbolStar, symbolCross, symbolDiamond } from 'd3-shape'
import { phenologyState } from './phenology_state'

// Symbols for displayed phenophases. Senescent records are not plotted.
const PHENO_SYMBOL = {
  'developing':  symbolCircle,
  'maturing':    symbolTriangle,
  'dormant':     symbolSquare,
  'perimature':  symbolCross,
  'oviscar':     symbolStar,
  'Free-living': symbolDiamond,
}

const GEN_COLOR = {
  'sexgen':  '#1f77b4',
  'agamic':  '#d62728',
  'unknown': '#555555',
}

// Human-readable legend labels for the encodings above.
const GEN_LABEL = {
  'sexgen':  'Sexual',
  'agamic':  'Agamic',
  'unknown': 'Unknown',
}

const PHENO_LABEL = {
  'developing':  'Developing',
  'maturing':    'Maturing',
  'dormant':     'Dormant',
  'perimature':  'Recently emerged',
  'oviscar':     'Oviposition scar',
  'Free-living': 'Free-living',
}

const MONTH_TICKS  = [1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335]
const MONTH_LABELS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
const POINT_AREA = 36
const POINT_OPACITY = 0.25

// Viability and insect-stage evidence are independent of gall phenophase.
function pointOpacity(d) {
  return d.viability === 'viable' || (typeof d.lifestage === 'string' && d.lifestage.trim() !== '')
    ? 1 : POINT_OPACITY
}

export default {
  mounted() {
    this.renderChart()
    this._resizeObserver = new ResizeObserver(() => {
      if (this.el.clientWidth !== this._lastWidth || this.el.clientHeight !== this._lastHeight) {
        this.renderChart(true)
      }
    })
    this._resizeObserver.observe(this.el)
    if (this.el.dataset.selectionEnabled === 'false') return
    // The chrome hook's Clear-selection button dispatches this event when
    // clicked. We clear the SVG rect (the moveBrush('') below uses the
    // restoringBrush flag so the d3 end handler doesn't echo) and then
    // explicitly publish the cleared state so the table + chrome
    // subscribers update.
    this._clearBrushListener = () => {
      if (this._moveBrush) this._moveBrush(null)
      phenologyState.setBrush(null)
    }
    document.addEventListener('phenology:clear-brush', this._clearBrushListener)

    // Redraw the Date-range / Seasonal-landmark selection overlay whenever the
    // selection changes (the select hook publishes on every input). The
    // brush's own rectangle is drawn by d3-brush, so click_drag mode draws
    // no custom overlay.
    this._selectionUnsub = phenologyState.subscribe(() => this.drawSelectionOverlay())
  },

  destroyed() {
    this._resizeObserver?.disconnect()
    select('body').selectAll('.phenology-tooltip').remove()
    if (this._clearBrushListener) {
      document.removeEventListener('phenology:clear-brush', this._clearBrushListener)
    }
    if (this._selectionUnsub) this._selectionUnsub()
  },

  // Only point-set changes drive a chart rebuild now. The brush state
  // lives entirely in `phenologyState` and the JS hooks — no server
  // roundtrip on brush gestures.
  updated() {
    const pointsRaw = this.el.dataset.points || '[]'
    if (this.el.dataset.selectionEnabled === 'false' || pointsRaw !== this._lastPointsRaw || this.el.dataset.latRange !== this._lastLatRange) {
      this.renderChart()
    } else {
      this.drawPredictions()
    }
  },

  renderChart(preserveBrush = false) {
    const pointsRaw = this.el.dataset.points || '[]'
    const points = JSON.parse(pointsRaw).filter(p => p.phenophase !== 'senescent' && Number.isFinite(p.lat) &&
      p.lat >= -90 && p.lat <= 90 && Number.isFinite(p.doy) && p.doy >= 1 && p.doy <= 366)
    const selectionEnabled = this.el.dataset.selectionEnabled !== 'false'
    const targetLats = selectionEnabled && points.length > 0 ? [] : JSON.parse(this.el.dataset.predictions || '[]')
      .map(p => p.target_lat).filter(Number.isFinite)
    this._lastPointsRaw = pointsRaw
    this._lastLatRange = this.el.dataset.latRange
    this._lastWidth = this.el.clientWidth
    this._lastHeight = this.el.clientHeight
    const previousBrush = selectionEnabled && preserveBrush ? phenologyState.brush : null

    // A full chart rebuild only happens on initial mount or when the
    // underlying obs set changed (filter applied). The LV wipes its
    // server-side selection on filter changes, so any prior client-side
    // brush is no longer meaningful — drop it so the table hook re-renders
    // the new full set.
    if (selectionEnabled && !preserveBrush) phenologyState.setBrush(null)

    select(this.el).selectAll('*').remove()
    this._moveBrush = null
    // Scales/overlay from a previous render are gone now; null them so the
    // selection subscriber (which can fire mid-rebuild via setBrush below)
    // skips until we rebuild them.
    this._x = null
    this._y = null
    this._overlayG = null
    if (points.length === 0 && targetLats.length === 0 && !this.el.dataset.latRange) {
      select(this.el).append('div')
        .style('padding', '40px')
        .style('text-align', 'center')
        .style('color', '#888')
        .text('No observations to display.')
      return
    }

    // On narrow screens the legend sits above the plot in two columns.
    const compact = this.el.clientWidth < 600
    const phaseCount = new Set(points.map(p => p.phenophase)).size
    const margin = { top: compact ? 46 + 18 * Math.max(3, phaseCount) : 20,
      right: compact ? 12 : 150, bottom: 50, left: 56 }
    const width  = this.el.clientWidth  - margin.left - margin.right
    const height = this.el.clientHeight - margin.top  - margin.bottom

    const svg = select(this.el)
      .append('svg')
        .attr('width',  width + margin.left + margin.right)
        .attr('height', height + margin.top  + margin.bottom)
      .append('g')
        .attr('transform', `translate(${margin.left},${margin.top})`)

    // Tooltip (singleton, attached to body for z-index sanity)
    const tooltip = select('body').selectAll('.phenology-tooltip').data([null])
      .join('div')
        .attr('class', 'phenology-tooltip')
        .style('position', 'absolute')
        .style('display', 'none')
        .style('visibility', 'hidden')
        .style('background', 'rgba(0, 0, 0, 0.85)')
        .style('color', '#fff')
        .style('padding', '6px 10px')
        .style('border-radius', '4px')
        .style('font-size', '12px')
        .style('line-height', '1.4')
        .style('pointer-events', 'none')
        .style('z-index', '1000')

    const x = scaleLinear().domain([-5, 371]).range([0, width])
    const latExtent = this.el.dataset.latRange ? JSON.parse(this.el.dataset.latRange)
      : extent([...points.map(p => p.lat), ...targetLats])
    const latPad = Math.max(1, (latExtent[1] - latExtent[0]) * 0.05)
    const y = scaleLinear().domain([latExtent[0] - latPad, latExtent[1] + latPad]).nice().range([height, 0])

    // Axes
    svg.append('g')
      .attr('transform', `translate(0,${height})`)
      .attr('class', 'month-axis')
      .call(axisBottom(x)
        .tickValues(MONTH_TICKS.filter((_, i) => width >= 400 || i % 3 === 0))
        .tickFormat(day => MONTH_LABELS[MONTH_TICKS.indexOf(day)]))

    svg.append('g').call(axisLeft(y).ticks(6))

    svg.append('text')
      .attr('x', width / 2).attr('y', height + margin.bottom - 8)
      .attr('text-anchor', 'middle').style('font-size', '12px').style('fill', '#666')
      .text('Day of year')

    svg.append('text')
      .attr('transform', 'rotate(-90)')
      .attr('x', -height / 2).attr('y', -margin.left + 16)
      .attr('text-anchor', 'middle').style('font-size', '12px').style('fill', '#666')
      .text('Latitude (°N)')

    // Brush layer — added BEFORE the points so points stay above and can
    // receive mouseover events for tooltips. d3-brush emits an "end" event
    // on mouseup; we translate the pixel selection back to data domain
    // and publish to `phenologyState`. Table + chrome hooks subscribe.
    // The chart-side moveBrush below uses `restoringBrush` to suppress the
    // d3 "end" event that fires when we programmatically clear the rect.
    let restoringBrush = false
    const chartBrush = brush()
      .extent([[0, 0], [width, height]])
      .on('end', ({ selection }) => {
        if (restoringBrush) return
        if (!selection) {
          phenologyState.setBrush(null)
          return
        }
        const [[x0, y0], [x1, y1]] = selection
        const bounds = {
          doy_min: Math.floor(x.invert(x0)),
          doy_max: Math.ceil(x.invert(x1)),
          // y axis is inverted in screen space — top pixel is highest lat,
          // so we take the min/max explicitly to stay generation-agnostic.
          lat_min: Math.min(y.invert(y0), y.invert(y1)),
          lat_max: Math.max(y.invert(y0), y.invert(y1)),
        }
        phenologyState.setBrush(bounds)
      })

    const brushG = selectionEnabled ? svg.append('g')
      .attr('class', 'brush')
      .call(chartBrush) : null

    // Selection overlay for the Date-range / Seasonal-landmark modes, drawn above
    // the brush background but below the points (so points stay visible on
    // the shading). pointer-events none so it never eats point hovers or
    // brush drags. Populated by drawSelectionOverlay().
    this._x = x
    this._y = y
    this._width = width
    this._height = height
    this._brushG = brushG
    this._overlayG = selectionEnabled ? svg.append('g')
      .attr('class', 'selection-overlay')
      .attr('pointer-events', 'none') : null
    this._predictionG = svg.append('g')
      .attr('class', 'prediction-overlay')
      .attr('pointer-events', 'none')
    const predictionClipId = `${this.el.id}-prediction-clip`
    svg.append('defs').append('clipPath').attr('id', predictionClipId)
      .append('rect').attr('width', width).attr('height', height)
    this._predictionG.attr('clip-path', `url(#${predictionClipId})`)
    this._overlayG?.attr('clip-path', `url(#${predictionClipId})`)

    // Programmatically clear the rectangle (called from the chrome's
    // Clear-selection listener). `restoringBrush` suppresses the d3 "end"
    // event the move below would otherwise emit.
    const moveBrush = (bounds) => {
      if (!brushG) return
      restoringBrush = true
      try {
        brushG.call(chartBrush.move, bounds ? [
          [x(bounds.doy_min), y(bounds.lat_max)], [x(bounds.doy_max), y(bounds.lat_min)]
        ] : null)
      } finally {
        restoringBrush = false
      }
    }
    this._moveBrush = moveBrush

    // Points — drawn on top of the brush overlay. Each path captures its
    // own mouseover; the brush still works for empty-area drag-selection.
    const symbolGen = symbol().size(POINT_AREA)
    // Composite ordinary symbols together before fading the layer, so repeated
    // records cannot build opacity and impersonate stronger evidence.
    const pointLayers = svg.selectAll('g.observation-layer')
      .data([POINT_OPACITY, 1]).enter().append('g')
      .attr('class', 'observation-layer')
      .attr('opacity', opacity => opacity)
    const hoverLayer = svg.append('g').attr('class', 'observation-hover-layer')
      .attr('pointer-events', 'none')
    pointLayers.selectAll('path.obs')
      .data(opacity => points.filter(d => pointOpacity(d) === opacity)).enter()
      .append('path')
        .attr('class', 'obs')
        .attr('d', d => symbolGen.type(PHENO_SYMBOL[d.phenophase] || symbolCircle)())
        .attr('transform', d => `translate(${x(d.doy)},${y(d.lat)})`)
        .attr('fill', d => GEN_COLOR[d.generation] || GEN_COLOR.unknown)
        .attr('fill-opacity', 1)
        .attr('stroke', '#222')
        .attr('stroke-opacity', 1)
        .attr('stroke-width', 0.4)
        .style('cursor', 'pointer')
        .style('pointer-events', 'all')
        .on('mouseover', function (event, d) {
          // A temporary copy escapes the muted layer without moving the hit
          // target or changing the permanent evidence ordering.
          hoverLayer.selectAll('*').remove()
          const copy = this.cloneNode(false)
          copy.setAttribute('class', 'observation-hover')
          copy.style.pointerEvents = 'none'
          hoverLayer.node().appendChild(copy)
          const speciesLine = d.species_name
            ? `<b>${escapeHtml(d.species_name)}</b><br>`
            : ''
          tooltip.style('display', 'block').style('visibility', 'visible')
            .html(`${speciesLine}<b>${escapeHtml(d.date)}</b>
                   <br>DOY ${d.doy} · lat ${d.lat.toFixed(2)}
                   <br>phenophase: ${escapeHtml(d.phenophase)}
                   <br>lifestage: ${escapeHtml(d.lifestage || '—')}
                   <br>viability: ${escapeHtml(d.viability || '—')}
                   <br>${escapeHtml([d.site, d.state, d.country].filter(Boolean).join(', ') || '—')}
                   <br><i>${escapeHtml(d.source_type)}</i>`)
        })
        .on('mousemove', function (event) {
          tooltip.style('top',  (event.pageY - 12) + 'px')
                 .style('left', (event.pageX + 12) + 'px')
        })
        .on('mouseout', function () {
          hoverLayer.selectAll('*').remove()
          tooltip.style('display', 'none').style('visibility', 'hidden')
        })

    // Keep interval shading below observations, but outlines above them in
    // both views. The foreground must not intercept observation tooltips.
    this._predictionLinesG = svg.append('g')
      .attr('class', 'prediction-lines')
      .attr('pointer-events', 'none')
      .attr('clip-path', `url(#${predictionClipId})`)

    // Legend in the right margin — color = generation, shape = phenophase.
    // Built only from the values actually present so it never lists an
    // encoding the current points don't use.
    this.drawLegend(svg, points, width, compact ? margin.top : 0)
    this._predictionLabelsG = svg.append('g').attr('class', 'prediction-labels')
      .attr('pointer-events', 'none')

    // Reflect the current selection (e.g. after a filter-driven rebuild the
    // user may already have a Date-range / Seasonal-landmark lens active).
    this.drawSelectionOverlay()
    this.drawPredictions()
    if (previousBrush) moveBrush(previousBrush)
  },

  // The server supplies both contours and target dates from ONE inverse.
  // Keep this separate from the selection lens, which never changes predictions.
  drawPredictions() {
    if (!this._predictionG || !this._x || !this._y) return
    const g = this._predictionG
    g.selectAll('*').remove()
    const lines = this._predictionLinesG
    lines.selectAll('*').remove()
    const labels = this._predictionLabelsG
    labels.selectAll('*').remove()
    const predictions = JSON.parse(this.el.dataset.predictions || '[]')
    const x = this._x, y = this._y
    const [latLo, latHi] = y.domain()
    const dateLabel = doy => new Date(Date.UTC(2023, 0, doy))
      .toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })
    predictions.forEach((p, i) => {
      const rows = p.contours.filter(r => r.lat >= latLo && r.lat <= latHi)
      if (rows.length < 2) return
      const color = GEN_COLOR[p.generation] || GEN_COLOR.unknown
      // Continuous lifted dates cross January without a false year-wide polygon.
      // Translate whole contours, then let the plot clip each annual copy.
      for (const shift of (p.wrap_year ? [-730, -365, 0, 365, 730] : [0])) {
      const low = rows.map(r => [x(r.low_doy + shift), y(r.lat)])
      const high = rows.map(r => [x(r.high_doy + shift), y(r.lat)])
      if (rows[0].outer_low_doy != null) {
        const outerLow = rows.map(r => [x(r.outer_low_doy + shift), y(r.lat)])
        const outerHigh = rows.map(r => [x(r.outer_high_doy + shift), y(r.lat)])
        g.append('path').attr('class', 'prediction-outer-band')
          .attr('d', toPath([...outerLow, ...outerHigh.reverse()]) + 'Z')
          .attr('fill', color).attr('fill-opacity', 0.055)
        lines.append('path').attr('class', 'prediction-median')
          .attr('d', toPath(rows.map(r => [x(r.median_doy + shift), y(r.lat)])))
          .attr('fill', 'none').attr('stroke', color).attr('stroke-width', 1.5)
          .attr('stroke-dasharray', '2,3')
      }
      if (p.event !== 'onset') {
        g.append('path').attr('d', toPath([...low, ...high.slice().reverse()]) + 'Z')
          .attr('fill', color).attr('fill-opacity', 0.07)
      }
      for (const edge of (p.event === 'onset' ? [low] : [low, high])) {
        const boundary = lines.append('path').attr('class', 'prediction-boundary').attr('d', toPath(edge))
          .attr('fill', 'none').attr('stroke', color).attr('stroke-width', 1.8)
          .attr('stroke-dasharray', p.event === 'rearing' ? '2,3' : ['emergence', 'adult_rearing', 'seasonal_observation'].includes(p.event) ? '6,4' : null)
        // A narrow white halo keeps same-colored dense observations from
        // swallowing the boundary. Lower all halos beneath the colored lines.
        boundary.clone(true).attr('class', 'prediction-boundary-halo')
          .attr('stroke', 'white').attr('stroke-width', 4).attr('stroke-opacity', 0.9).lower()
      }
      }
      if (p.target_lat < latLo || p.target_lat > latHi) return
      if (i === 0) {
        labels.append('line').attr('x1', 0).attr('x2', this._width)
          .attr('y1', y(p.target_lat)).attr('y2', y(p.target_lat))
          .attr('stroke', '#374151').attr('stroke-dasharray', '3,4')
        labels.append('text').attr('x', this._width - 4).attr('y', y(p.target_lat) - 7)
          .attr('text-anchor', 'end').attr('fill', '#374151').style('font-size', '11px')
          .text(`${p.target_lat}° target`)
      }
      const dates = p.event === 'onset'
        ? [[p.low_doy, 'start']]
        : [[p.low_doy, 'end'], [p.high_doy, 'start']]
      for (const [doy, anchor] of dates) {
        labels.append('circle').attr('class', 'prediction-date-marker')
          .attr('data-doy', doy).attr('cx', x(doy)).attr('cy', y(p.target_lat))
          .attr('r', 4).attr('fill', 'white').attr('stroke', color).attr('stroke-width', 2)
        labels.append('text').attr('x', x(doy) + (anchor === 'end' ? -7 : 7))
          .attr('y', y(p.target_lat) + 17 + i * 14).attr('text-anchor', anchor)
          .attr('fill', color).attr('stroke', 'white').attr('stroke-width', 3)
          .attr('paint-order', 'stroke').style('font-size', '11px').text(dateLabel(doy))
      }
    })
    if (predictions.length && (predictions[0].target_lat < latLo || predictions[0].target_lat > latHi)) {
      labels.append('text').attr('x', 8).attr('y', 15).attr('fill', '#374151')
        .style('font-size', '12px').text('Target latitude is outside this chart; projected dates below are extrapolated.')
    }
  },

  // Draw the Date-range (vertical band) or Seasonal-landmark (curved clock
  // band) selection onto the chart, matching what applySelection filters in
  // the table. Cleared and redrawn on every selection change. click_drag
  // draws nothing here — d3-brush renders its own rectangle.
  drawSelectionOverlay() {
    const g = this._overlayG
    const x = this._x
    const y = this._y
    if (!g || !x || !y) return

    const sel = phenologyState.selection || { mode: 'click_drag' }

    // Hide the brush rectangle in the non-brush modes without clearing it, so
    // it (and its d3-brush selection) reappears in place on returning to
    // Click & drag. display:none also disables brushing in those modes.
    if (this._brushG) this._brushG.style('display', sel.mode === 'click_drag' ? null : 'none')

    g.selectAll('*').remove()
    const h = this._height
    const GREEN = '#2e7d32'

    const band = (x0, x1) =>
      g.append('rect')
        .attr('x', x0).attr('y', 0)
        .attr('width', Math.max(0, x1 - x0)).attr('height', h)
        .attr('fill', GREEN).attr('fill-opacity', 0.12)

    const vline = (px) =>
      g.append('line')
        .attr('x1', px).attr('y1', 0).attr('x2', px).attr('y2', h)
        .attr('stroke', GREEN).attr('stroke-width', 1).attr('stroke-dasharray', '4 3')

    if (sel.mode === 'date_range') {
      if (sel.doy == null || sel.days == null) return
      const lo = mod365(sel.doy - sel.days)
      const hi = mod365(sel.doy + sel.days)
      // A window that wraps the new year becomes two bands.
      const bands = lo <= hi ? [[lo, hi]] : [[0, hi], [lo, 365]]
      bands.forEach(([a, b]) => band(x(a), x(b)))
      ;[lo, hi].forEach((d) => vline(x(d)))
    } else if (sel.mode === 'seasonal_landmark') {
      if (!sel.clock || !sel.window) return
      const {clock, window: {low, high}} = sel
      const latMin = Math.max(y.domain()[0], clock.latitudes[0])
      const latMax = Math.min(y.domain()[1], clock.latitudes.at(-1))
      if (latMax <= latMin) return
      if (high - low >= 365) {
        g.append('rect').attr('class', 'landmark-selection-band')
          .attr('x', 0).attr('y', y(latMax)).attr('width', this._width)
          .attr('height', y(latMin) - y(latMax)).attr('fill', GREEN).attr('fill-opacity', 0.12)
        return
      }
      // At fixed phase, inverse dates interpolate linearly between reference
      // rows. Use those exact knots, including the visible domain boundaries.
      const samples = [...new Set([latMin, ...clock.latitudes.filter(lat =>
        lat > latMin && lat < latMax), latMax])]
      for (const shift of [-730, -365, 0, 365, 730]) {
        const left = samples.map(lat => [x(clock.inverse(low, lat) + shift), y(lat)])
        const right = samples.map(lat => [x(clock.inverse(high, lat) + shift), y(lat)])
        g.append('path').attr('class', 'landmark-selection-band')
          .attr('d', toPath([...left, ...right.slice().reverse()]) + 'Z')
          .attr('fill', GREEN).attr('fill-opacity', 0.12)
        for (const edge of [left, right]) {
          g.append('path').attr('class', 'landmark-selection-edge').attr('d', toPath(edge))
            .attr('fill', 'none').attr('stroke', GREEN).attr('stroke-width', 1)
            .attr('stroke-dasharray', '4 3')
        }
      }
    }
    // click_drag: nothing — the brush draws its own rectangle.
  },

  drawLegend(svg, points, width, topSpace = 0) {
    let legendX = topSpace ? -32 : width + 16
    const legendSymbol = symbol().size(70)
    const legend = svg.append('g').attr('class', 'legend')
    let ly = topSpace ? -topSpace + 16 : 4

    const heading = (text) => {
      legend.append('text')
        .attr('x', legendX).attr('y', ly).attr('dominant-baseline', 'hanging')
        .style('font-size', '11px').style('font-weight', '600').style('fill', '#444')
        .text(text)
      ly += 18
    }

    const row = (type, fill, label) => {
      legend.append('path')
        .attr('d', legendSymbol.type(type)())
        .attr('transform', `translate(${legendX + 6},${ly + 3})`)
        .attr('fill', fill).attr('fill-opacity', 0.7)
        .attr('stroke', '#222').attr('stroke-width', 0.4)
      legend.append('text')
        .attr('x', legendX + 20).attr('y', ly + 3).attr('dominant-baseline', 'middle')
        .style('font-size', '11px').style('fill', '#444')
        .text(label)
      ly += 18
    }

    const gens = Object.keys(GEN_COLOR)
      .filter((g) => points.some((d) => (d.generation || 'unknown') === g))
    if (gens.length) {
      heading('Generation')
      gens.forEach((g) => row(symbolCircle, GEN_COLOR[g], GEN_LABEL[g] || g))
      ly += 8
    }

    const phenos = Object.keys(PHENO_SYMBOL)
      .filter((p) => points.some((d) => d.phenophase === p))
    if (phenos.length) {
      if (topSpace) {
        legendX = Math.max(100, width / 2)
        ly = -topSpace + 16
      }
      heading('Phenophase')
      phenos.forEach((p) => row(PHENO_SYMBOL[p], '#777', PHENO_LABEL[p] || p))
    }
  }
}

function escapeHtml(s) {
  return String(s == null ? '' : s).replace(/[&<>"']/g,
    c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
}

function mod365(v) {
  return ((v % 365) + 365) % 365
}

function toPath(points) {
  return points.map((p, i) => `${i === 0 ? 'M' : 'L'}${p[0]},${p[1]}`).join(' ')
}
