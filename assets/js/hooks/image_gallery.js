// ImageGallery hook for keyboard navigation, lightbox, and attribution updates
const ImageGallery = {
  mounted() {
    this.currentIndex = 0
    this.images = JSON.parse(this.el.dataset.images || "[]")
    this.lightboxOpen = false
    this.infoOpen = false

    // Keyboard navigation
    this.keyHandler = (e) => {
      if (e.key === "ArrowLeft") {
        this.prevImage()
      } else if (e.key === "ArrowRight") {
        this.nextImage()
      } else if (e.key === "Escape") {
        if (this.lightboxOpen) this.closeLightbox()
        if (this.infoOpen) this.closeInfo()
      }
    }

    this.el.addEventListener("keydown", this.keyHandler)

    // Navigation button handlers
    this.el.querySelectorAll("[data-prev]").forEach(btn => {
      btn.addEventListener("click", () => this.prevImage())
    })
    this.el.querySelectorAll("[data-next]").forEach(btn => {
      btn.addEventListener("click", () => this.nextImage())
    })

    // Lightbox handlers
    this.el.querySelectorAll("[data-open-lightbox]").forEach(btn => {
      btn.addEventListener("click", () => this.openLightbox())
    })
    this.el.querySelectorAll("[data-close-lightbox]").forEach(btn => {
      btn.addEventListener("click", () => this.closeLightbox())
    })

    // Info dialog handlers
    this.el.querySelectorAll("[data-open-info]").forEach(btn => {
      btn.addEventListener("click", () => this.openInfo())
    })
    this.el.querySelectorAll("[data-close-info]").forEach(btn => {
      btn.addEventListener("click", () => this.closeInfo())
    })
  },
  destroyed() {
    this.el.removeEventListener("keydown", this.keyHandler)
  },
  prevImage() {
    this.currentIndex = this.currentIndex > 0 ? this.currentIndex - 1 : this.images.length - 1
    this.updateDisplay()
  },
  nextImage() {
    this.currentIndex = this.currentIndex < this.images.length - 1 ? this.currentIndex + 1 : 0
    this.updateDisplay()
  },
  updateDisplay() {
    const img = this.images[this.currentIndex]
    if (!img) return

    // Update main image
    const mainImg = this.el.querySelector("[data-main-image]")
    if (mainImg) {
      mainImg.src = img.src
      mainImg.alt = img.alt || ""
    }

    // Update lightbox image
    const lightboxImg = this.el.querySelector("[data-lightbox-image]")
    if (lightboxImg) {
      lightboxImg.src = img.src
      lightboxImg.alt = img.alt || ""
    }

    // Update counter
    this.el.querySelectorAll("[data-counter]").forEach(counter => {
      counter.textContent = `${this.currentIndex + 1} / ${this.images.length}`
    })

    // Update caption
    const caption = this.el.querySelector("[data-caption]")
    if (caption) {
      caption.textContent = img.caption || ""
      caption.classList.toggle("hidden", !img.caption)
    }

    // Update attribution elements
    const sourceLink = this.el.querySelector("[data-source-link]")
    if (sourceLink) {
      sourceLink.href = img.sourcelink || "#"
      sourceLink.parentElement.classList.toggle("hidden", !img.sourcelink)
    }

    const creator = this.el.querySelector("[data-creator]")
    if (creator) creator.textContent = img.creator || ""

    const hasLicenseLink = !!img.licenselink

    const licenseLink = this.el.querySelector("[data-license-link]")
    if (licenseLink) {
      licenseLink.href = img.licenselink || "#"
      licenseLink.classList.toggle("hidden", !hasLicenseLink)
      const licenseSpan = licenseLink.querySelector("[data-license]")
      if (licenseSpan) licenseSpan.textContent = img.license || ""
    }

    const licenseNoLink = this.el.querySelector("[data-license-nolink]")
    if (licenseNoLink) {
      licenseNoLink.textContent = img.license || ""
      licenseNoLink.classList.toggle("hidden", hasLicenseLink)
    }

    const licenseTooltip = this.el.querySelector("[data-license-tooltip]")
    if (licenseTooltip) licenseTooltip.textContent = img.license || "No license"

    // Update info dialog elements
    const infoImage = this.el.querySelector("[data-info-image]")
    if (infoImage) infoImage.src = img.src

    const infoSource = this.el.querySelector("[data-info-source]")
    if (infoSource) {
      infoSource.href = img.sourcelink || "#"
      infoSource.textContent = img.source_title || img.sourcelink || ""
    }

    const infoLicenseLink = this.el.querySelector("[data-info-license-link]")
    if (infoLicenseLink) {
      infoLicenseLink.href = img.licenselink || "#"
      infoLicenseLink.textContent = img.license || ""
      infoLicenseLink.classList.toggle("hidden", !hasLicenseLink)
    }

    const infoLicenseNoLink = this.el.querySelector("[data-info-license-nolink]")
    if (infoLicenseNoLink) {
      infoLicenseNoLink.textContent = img.license || ""
      infoLicenseNoLink.classList.toggle("hidden", hasLicenseLink)
    }

    const infoAttribution = this.el.querySelector("[data-info-attribution]")
    if (infoAttribution) infoAttribution.textContent = img.attribution || ""

    const infoCreator = this.el.querySelector("[data-info-creator]")
    if (infoCreator) infoCreator.textContent = img.creator || ""

    const infoUploader = this.el.querySelector("[data-info-uploader]")
    if (infoUploader) infoUploader.textContent = img.uploader || ""

    const infoLastchangedby = this.el.querySelector("[data-info-lastchangedby]")
    if (infoLastchangedby) infoLastchangedby.textContent = img.lastchangedby || ""

    const infoCaption = this.el.querySelector("[data-info-caption]")
    if (infoCaption) infoCaption.textContent = img.caption || ""

    // Update lightbox attribution elements
    const lightboxSourceLink = this.el.querySelector("[data-lightbox-source-link]")
    if (lightboxSourceLink) lightboxSourceLink.href = img.sourcelink || "#"

    const lightboxCreator = this.el.querySelector("[data-lightbox-creator]")
    if (lightboxCreator) lightboxCreator.textContent = img.creator || ""

    const lightboxLicenseLink = this.el.querySelector("[data-lightbox-license-link]")
    if (lightboxLicenseLink) {
      lightboxLicenseLink.href = img.licenselink || "#"
      lightboxLicenseLink.classList.toggle("hidden", !hasLicenseLink)
      const lightboxLicenseSpan = lightboxLicenseLink.querySelector("[data-lightbox-license]")
      if (lightboxLicenseSpan) lightboxLicenseSpan.textContent = img.license || ""
    }

    const lightboxLicenseNoLink = this.el.querySelector("[data-lightbox-license-nolink]")
    if (lightboxLicenseNoLink) {
      lightboxLicenseNoLink.textContent = img.license || ""
      lightboxLicenseNoLink.classList.toggle("hidden", hasLicenseLink)
    }

    // Push event to server if needed
    this.pushEvent("gallery_index_changed", {index: this.currentIndex})
  },
  openLightbox() {
    this.lightboxOpen = true
    const lightbox = this.el.querySelector("[data-lightbox]")
    if (lightbox) lightbox.showModal()
  },
  closeLightbox() {
    this.lightboxOpen = false
    const lightbox = this.el.querySelector("[data-lightbox]")
    if (lightbox) lightbox.close()
  },
  openInfo() {
    this.infoOpen = true
    const info = this.el.querySelector("[data-info-dialog]")
    if (info) info.showModal()
  },
  closeInfo() {
    this.infoOpen = false
    const info = this.el.querySelector("[data-info-dialog]")
    if (info) info.close()
  }
}

export default ImageGallery
