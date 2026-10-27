/**
 * SortableImages Hook
 *
 * Enables drag-and-drop reordering of images in a grid.
 * The first image in the order becomes the default image.
 *
 * The new order goes to the hook element's LiveComponent
 * (`pushEventTo(this.el)`), or to the LiveView when the element is in none.
 */

const SortableImages = {
  mounted() {
    this.container = this.el
    this.draggingEl = null
    this.dropTarget = null

    this.setupListeners()
    this.makeDraggable()
  },

  updated() {
    // Re-initialize draggable attributes when LiveView updates the DOM
    this.makeDraggable()
  },

  setupListeners() {
    // Use event delegation on the container
    this.container.addEventListener("dragstart", (e) => this.handleDragStart(e))
    this.container.addEventListener("dragover", (e) => this.handleDragOver(e))
    this.container.addEventListener("dragend", (e) => this.handleDragEnd(e))
  },

  makeDraggable() {
    // Make all image items draggable
    this.container.querySelectorAll("[data-image-id]").forEach(item => {
      item.setAttribute("draggable", "true")
    })
  },

  getImageItem(el) {
    // Find the closest image item from an event target
    return el.closest("[data-image-id]")
  },

  handleDragStart(e) {
    const item = this.getImageItem(e.target)
    if (!item) return

    this.draggingEl = item
    this.originalIndex = this.getItemIndex(item)

    // Visual feedback
    setTimeout(() => {
      item.classList.add("opacity-50")
    }, 0)

    e.dataTransfer.effectAllowed = "move"
    e.dataTransfer.setData("text/plain", item.dataset.imageId)
  },

  handleDragOver(e) {
    e.preventDefault()
    e.dataTransfer.dropEffect = "move"

    if (!this.draggingEl) return

    const targetItem = this.getImageItem(e.target)
    if (!targetItem || targetItem === this.draggingEl) return

    // Determine if we should insert before or after the target
    const rect = targetItem.getBoundingClientRect()
    const midpoint = rect.left + rect.width / 2
    const insertBefore = e.clientX < midpoint

    // Move the dragging element in the DOM
    if (insertBefore) {
      this.container.insertBefore(this.draggingEl, targetItem)
    } else {
      this.container.insertBefore(this.draggingEl, targetItem.nextSibling)
    }
  },

  handleDragEnd(e) {
    if (!this.draggingEl) return

    // Remove visual feedback
    this.draggingEl.classList.remove("opacity-50")

    // Check if position changed
    const newIndex = this.getItemIndex(this.draggingEl)
    if (newIndex !== this.originalIndex) {
      // Get new order and send to server
      const newOrder = Array.from(this.container.querySelectorAll("[data-image-id]"))
        .map(el => parseInt(el.dataset.imageId, 10))

      this.pushEventTo(this.el, "reorder_images", { order: newOrder })
    }

    this.draggingEl = null
    this.originalIndex = null
  },

  getItemIndex(item) {
    const items = Array.from(this.container.querySelectorAll("[data-image-id]"))
    return items.indexOf(item)
  }
}

export default SortableImages
