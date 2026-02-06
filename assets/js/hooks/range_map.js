/**
 * RangeMap LiveView Hook
 *
 * Displays a choropleth map of US and Canadian states/provinces.
 * Uses D3.js for geographic projection and rendering.
 *
 * Data attributes:
 *   data-in-range: JSON array of postal codes in range (e.g., ["CA", "TX"])
 *   data-excluded-range: JSON array of postal codes excluded (optional)
 *   data-editable: "true" if regions are clickable (optional)
 */

import { geoPath, geoConicEqualArea } from 'd3-geo'
import { zoom } from 'd3-zoom'
import { select } from 'd3-selection'
import { feature } from 'topojson-client'

// Projection matching V1: geoConicEqualArea configured for US/Canada
const projection = geoConicEqualArea()
  .center([-4, 48])
  .parallels([29.5, 45.5])
  .rotate([96, 0, 0])
  .scale(750)
  .translate([400, 300])

const path = geoPath(projection)

// Color scheme
const COLORS = {
  inRange: '#228B22',      // ForestGreen (gall & host)
  excluded: '#FCA5A5',     // Light red (host only, excluded from range)
  default: '#FFFFFF',      // White (neither gall nor host)
  stroke: '#333333',       // Dark gray stroke
  hoverStroke: '#000000'   // Black stroke on hover
}

const RangeMap = {
  mounted() {
    this.features = []
    this.lakeFeatures = []
    this.inRange = new Set(JSON.parse(this.el.dataset.inRange || '[]'))
    this.excludedRange = new Set(JSON.parse(this.el.dataset.excludedRange || '[]'))
    this.editable = this.el.dataset.editable === 'true'
    this.modalOpen = false
    this.transform = { k: 1, x: 0, y: 0 }
    this.zoomBehavior = null

    // Listen for range updates from the server (used with phx-update="ignore")
    this.handleEvent('range-update', ({ in_range, excluded_range }) => {
      this.inRange = new Set(in_range || [])
      this.excludedRange = new Set(excluded_range || [])
      if (this.features.length > 0) {
        this.updateColors()
      }
    })

    this.loadTopology()
  },

  updated() {
    // Re-parse data attributes when LiveView updates
    this.inRange = new Set(JSON.parse(this.el.dataset.inRange || '[]'))
    this.excludedRange = new Set(JSON.parse(this.el.dataset.excludedRange || '[]'))
    this.editable = this.el.dataset.editable === 'true'

    // Re-render if features are loaded
    if (this.features.length > 0) {
      this.render()
    }
  },

  async loadTopology() {
    try {
      const res = await fetch('/data/usa-can-topo.json')
      const topology = await res.json()
      this.features = feature(topology, topology.objects.ne_10m_admin_1_states_provinces).features

      // Load Great Lakes if available
      if (topology.objects.ne_10m_lakes) {
        this.lakeFeatures = feature(topology, topology.objects.ne_10m_lakes).features
      } else {
        this.lakeFeatures = []
      }

      this.render()
    } catch (err) {
      console.error('Failed to load map topology:', err)
      this.el.innerHTML = '<p class="text-red-500">Failed to load map data</p>'
    }
  },

  getFill(code) {
    // On editable maps (admin), show excluded regions in red
    if (this.editable && this.excludedRange.has(code)) return COLORS.excluded
    // Show in-range regions in green
    if (this.inRange.has(code) && !this.excludedRange.has(code)) return COLORS.inRange
    // Everything else (not in range or excluded on public pages) is white
    return COLORS.default
  },

  // Update colors of existing paths without full re-render (preserves modal state)
  updateColors() {
    // Update thumbnail map
    const thumbnailPaths = this.el.querySelectorAll('.range-map-thumbnail path[data-code]')
    thumbnailPaths.forEach(pathEl => {
      const code = pathEl.getAttribute('data-code')
      pathEl.setAttribute('fill', this.getFill(code))
    })

    // Update modal map if open
    const modalPaths = this.el.querySelectorAll('.range-map-modal path[data-code]')
    modalPaths.forEach(pathEl => {
      const code = pathEl.getAttribute('data-code')
      pathEl.setAttribute('fill', this.getFill(code))
    })
  },

  render() {
    // Clear existing content
    this.el.innerHTML = ''

    // Create container structure
    const container = document.createElement('div')
    container.className = 'range-map-container relative'

    // Create tooltip first so SVG can reference it
    const tooltip = document.createElement('div')
    tooltip.className = 'range-map-tooltip hidden absolute bg-gray-800 text-white text-sm px-2 py-1 rounded pointer-events-none z-50'
    tooltip.id = `${this.el.id}-tooltip`
    container.appendChild(tooltip)

    // Create thumbnail SVG (pass container for tooltip positioning)
    const thumbnailWrapper = document.createElement('div')
    thumbnailWrapper.className = 'range-map-thumbnail cursor-pointer'
    thumbnailWrapper.setAttribute('role', 'button')
    thumbnailWrapper.setAttribute('tabindex', '0')
    thumbnailWrapper.setAttribute('aria-label', 'Click to expand map')

    const svg = this.createSvg(false, container)
    thumbnailWrapper.appendChild(svg)

    // Add "Click to expand" hint
    const hint = document.createElement('div')
    hint.className = 'text-xs text-gray-500 text-center mt-1'
    hint.textContent = 'Click to expand'
    thumbnailWrapper.appendChild(hint)

    // Click handler for modal
    thumbnailWrapper.addEventListener('click', () => this.openModal())
    thumbnailWrapper.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault()
        this.openModal()
      }
    })

    container.appendChild(thumbnailWrapper)

    // Create modal (hidden by default)
    const modal = this.createModal()
    container.appendChild(modal)

    this.el.appendChild(container)
  },

  createSvg(forModal = false, tooltipContainer = null) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg')
    svg.setAttribute('viewBox', '0 0 800 600')
    svg.setAttribute('class', forModal ? 'w-full h-full' : 'w-full max-w-md')
    svg.setAttribute('role', 'img')
    svg.setAttribute('aria-label', 'Geographic range map showing US and Canadian states/provinces')

    // Background (ocean)
    const bg = document.createElementNS('http://www.w3.org/2000/svg', 'rect')
    bg.setAttribute('width', '800')
    bg.setAttribute('height', '600')
    bg.setAttribute('fill', '#ADD8E6')  // Light blue to match lakes
    svg.appendChild(bg)

    // Group for paths (will be transformed in modal)
    const g = document.createElementNS('http://www.w3.org/2000/svg', 'g')
    g.setAttribute('class', 'map-paths')

    // Render each state/province feature first
    this.features.forEach(feature => {
      const pathEl = document.createElementNS('http://www.w3.org/2000/svg', 'path')
      const code = feature.properties.postal
      const name = feature.properties.name

      pathEl.setAttribute('d', path(feature))
      pathEl.setAttribute('fill', this.getFill(code))
      pathEl.setAttribute('stroke', COLORS.stroke)
      pathEl.setAttribute('stroke-width', forModal ? '0.5' : '1')
      pathEl.setAttribute('data-code', code)
      pathEl.setAttribute('data-name', name)

      if (this.editable) {
        pathEl.classList.add('cursor-pointer')
      }

      // Hover effects - use provided container or default
      const container = tooltipContainer || this.el
      pathEl.addEventListener('mouseenter', (e) => this.showTooltip(e, name, code, container))
      pathEl.addEventListener('mousemove', (e) => this.moveTooltip(e, container))
      pathEl.addEventListener('mouseleave', () => this.hideTooltip(container))

      // Click handler for editable mode
      if (this.editable) {
        pathEl.addEventListener('click', (e) => {
          e.stopPropagation() // Prevent opening modal when clicking regions
          this.pushEvent('toggle_region', { code })
        })
      }

      g.appendChild(pathEl)
    })

    // Render Great Lakes on TOP of states so they're visible
    if (this.lakeFeatures && this.lakeFeatures.length > 0) {
      this.lakeFeatures.forEach(lake => {
        const pathEl = document.createElementNS('http://www.w3.org/2000/svg', 'path')
        pathEl.setAttribute('d', path(lake))
        pathEl.setAttribute('fill', '#ADD8E6')  // Light blue for water
        pathEl.setAttribute('stroke', '#4682B4')  // Steel blue outline
        pathEl.setAttribute('stroke-width', forModal ? '0.5' : '1')
        pathEl.setAttribute('data-name', lake.properties.name || 'Lake')
        g.appendChild(pathEl)
      })
    }

    svg.appendChild(g)
    return svg
  },

  createModal() {
    const modal = document.createElement('dialog')
    modal.className = 'range-map-modal p-0 rounded-lg shadow-xl backdrop:bg-black/50'
    modal.classList.add('w-[90vw]', 'h-[80vh]', 'max-w-[1200px]')
    modal.id = `${this.el.id}-modal`

    const modalContent = document.createElement('div')
    modalContent.className = 'relative w-full h-full'

    // Close button
    const closeBtn = document.createElement('button')
    closeBtn.className = 'absolute top-2 right-2 z-10 p-2 bg-white rounded-full shadow hover:bg-gray-100'
    closeBtn.innerHTML = '<svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/></svg>'
    closeBtn.setAttribute('aria-label', 'Close map')
    closeBtn.addEventListener('click', () => this.closeModal())

    // Zoom controls
    const zoomControls = document.createElement('div')
    zoomControls.className = 'absolute bottom-4 right-4 z-10 flex flex-col gap-1'

    const zoomIn = document.createElement('button')
    zoomIn.className = 'p-2 bg-white rounded shadow hover:bg-gray-100'
    zoomIn.innerHTML = '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"/></svg>'
    zoomIn.setAttribute('aria-label', 'Zoom in')
    zoomIn.addEventListener('click', () => this.zoomIn())

    const zoomOut = document.createElement('button')
    zoomOut.className = 'p-2 bg-white rounded shadow hover:bg-gray-100'
    zoomOut.innerHTML = '<svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20 12H4"/></svg>'
    zoomOut.setAttribute('aria-label', 'Zoom out')
    zoomOut.addEventListener('click', () => this.zoomOut())

    const resetZoom = document.createElement('button')
    resetZoom.className = 'p-2 bg-white rounded shadow hover:bg-gray-100 text-xs font-medium'
    resetZoom.textContent = 'Reset'
    resetZoom.setAttribute('aria-label', 'Reset zoom')
    resetZoom.addEventListener('click', () => this.resetZoom())

    zoomControls.appendChild(zoomIn)
    zoomControls.appendChild(zoomOut)
    zoomControls.appendChild(resetZoom)

    // Pan/zoom hint
    const hint = document.createElement('div')
    hint.className = 'absolute bottom-4 left-4 z-10 bg-white/90 px-3 py-1.5 rounded shadow text-sm text-gray-600'
    hint.textContent = 'Drag to pan, scroll to zoom'

    // SVG container
    const svgContainer = document.createElement('div')
    svgContainer.className = 'w-full h-full'
    svgContainer.id = `${this.el.id}-modal-svg`

    // Modal tooltip
    const tooltip = document.createElement('div')
    tooltip.className = 'range-map-tooltip hidden absolute bg-gray-800 text-white text-sm px-2 py-1 rounded pointer-events-none z-50'
    tooltip.id = `${this.el.id}-modal-tooltip`

    modalContent.appendChild(closeBtn)
    modalContent.appendChild(zoomControls)
    modalContent.appendChild(hint)
    modalContent.appendChild(svgContainer)
    modalContent.appendChild(tooltip)
    modal.appendChild(modalContent)

    // Close on escape or backdrop click
    modal.addEventListener('close', () => {
      this.modalOpen = false
    })
    modal.addEventListener('click', (e) => {
      if (e.target === modal) {
        this.closeModal()
      }
    })

    return modal
  },

  openModal() {
    const modal = this.el.querySelector('.range-map-modal')
    if (!modal) return

    modal.showModal()
    this.modalOpen = true

    // Create modal SVG with zoom
    const svgContainer = modal.querySelector(`#${this.el.id}-modal-svg`)
    const modalContent = svgContainer.parentElement
    svgContainer.innerHTML = ''

    const svg = this.createSvg(true, modalContent)
    svg.id = `${this.el.id}-zoom-svg`
    svgContainer.appendChild(svg)

    // Initialize D3 zoom
    this.transform = { k: 1, x: 0, y: 0 }
    this.zoomBehavior = zoom()
      .scaleExtent([0.5, 8])
      .on('zoom', (event) => {
        this.transform = event.transform
        const g = svg.querySelector('.map-paths')
        g.setAttribute('transform', `translate(${this.transform.x}, ${this.transform.y}) scale(${this.transform.k})`)

        // Adjust stroke width for zoom level
        g.querySelectorAll('path').forEach(path => {
          path.setAttribute('stroke-width', 0.5 / this.transform.k)
        })
      })

    select(svg).call(this.zoomBehavior)
  },

  closeModal() {
    const modal = this.el.querySelector('.range-map-modal')
    if (modal) {
      modal.close()
      this.modalOpen = false
    }
  },

  zoomIn() {
    const svg = this.el.querySelector(`#${this.el.id}-zoom-svg`)
    if (svg && this.zoomBehavior) {
      select(svg).transition().duration(300).call(this.zoomBehavior.scaleBy, 1.5)
    }
  },

  zoomOut() {
    const svg = this.el.querySelector(`#${this.el.id}-zoom-svg`)
    if (svg && this.zoomBehavior) {
      select(svg).transition().duration(300).call(this.zoomBehavior.scaleBy, 0.67)
    }
  },

  resetZoom() {
    const svg = this.el.querySelector(`#${this.el.id}-zoom-svg`)
    if (svg && this.zoomBehavior) {
      select(svg).transition().duration(300).call(this.zoomBehavior.transform, { k: 1, x: 0, y: 0 })
    }
  },

  showTooltip(event, name, code, container = null) {
    const el = container || this.el
    const tooltip = el.querySelector('.range-map-tooltip')
    if (!tooltip) return

    let status = ''
    if (this.inRange.has(code)) {
      status = ' (in range)'
    } else if (this.excludedRange.has(code)) {
      status = ' (excluded)'
    }

    tooltip.textContent = `${name} (${code})${status}`
    tooltip.classList.remove('hidden')
    this.moveTooltip(event, container)
  },

  moveTooltip(event, container = null) {
    const el = container || this.el
    const tooltip = el.querySelector('.range-map-tooltip')
    if (!tooltip) return

    const rect = el.getBoundingClientRect()
    const x = event.clientX - rect.left + 10
    const y = event.clientY - rect.top - 25

    tooltip.style.left = `${x}px`
    tooltip.style.top = `${y}px`
  },

  hideTooltip(container = null) {
    const el = container || this.el
    const tooltip = el.querySelector('.range-map-tooltip')
    if (tooltip) {
      tooltip.classList.add('hidden')
    }
  }
}

export default RangeMap
