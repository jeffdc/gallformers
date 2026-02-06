/**
 * ImageUpload Hook
 *
 * Handles drag-drop image upload with:
 * - File type validation (images only)
 * - Client-side preview before upload
 * - Progress indicator during upload
 * - Direct upload to S3 using presigned URLs
 */

const ImageUpload = {
  mounted() {
    this.maxFiles = parseInt(this.el.dataset.maxFiles || "4", 10)
    this.acceptedTypes = (this.el.dataset.acceptedTypes || "image/jpeg,image/png,image/jpg").split(",")
    this.speciesId = this.el.dataset.speciesId

    this.files = []
    this.uploads = new Map() // Track upload progress

    // Get DOM elements
    this.dropzone = this.el.querySelector("[data-dropzone]")
    this.fileInput = this.el.querySelector("[data-file-input]")
    this.previewContainer = this.el.querySelector("[data-preview-container]")
    this.uploadButton = this.el.querySelector("[data-upload-button]")
    this.progressContainer = this.el.querySelector("[data-progress-container]")

    this.setupEventListeners()
  },

  setupEventListeners() {
    // Dropzone events
    if (this.dropzone) {
      this.dropzone.addEventListener("dragover", (e) => this.handleDragOver(e))
      this.dropzone.addEventListener("dragleave", (e) => this.handleDragLeave(e))
      this.dropzone.addEventListener("drop", (e) => this.handleDrop(e))
      this.dropzone.addEventListener("click", () => this.fileInput?.click())
    }

    // File input change
    if (this.fileInput) {
      this.fileInput.addEventListener("change", (e) => this.handleFileSelect(e))
    }

    // Upload button
    if (this.uploadButton) {
      this.uploadButton.addEventListener("click", () => this.uploadFiles())
    }

    // Listen for presigned URL responses from the server
    this.handleEvent("presigned_urls", ({ urls }) => {
      this.executeUploads(urls)
    })

    // Listen for upload completion acknowledgment
    this.handleEvent("upload_complete", ({ message }) => {
      this.showSuccess(message)
      this.resetForm()
    })

    // Listen for errors from server
    this.handleEvent("upload_error", ({ message }) => {
      this.showError(message)
    })
  },

  handleDragOver(e) {
    e.preventDefault()
    e.stopPropagation()
    this.dropzone.classList.add("border-gf-maroon", "bg-gf-sky-blue/20")
  },

  handleDragLeave(e) {
    e.preventDefault()
    e.stopPropagation()
    this.dropzone.classList.remove("border-gf-maroon", "bg-gf-sky-blue/20")
  },

  handleDrop(e) {
    e.preventDefault()
    e.stopPropagation()
    this.dropzone.classList.remove("border-gf-maroon", "bg-gf-sky-blue/20")

    const files = Array.from(e.dataTransfer.files)
    this.addFiles(files)
  },

  handleFileSelect(e) {
    const files = Array.from(e.target.files)
    this.addFiles(files)
    // Reset input to allow selecting the same file again
    e.target.value = ""
  },

  addFiles(newFiles) {
    // Filter to only accepted types
    const validFiles = newFiles.filter(file => {
      if (!this.acceptedTypes.includes(file.type)) {
        this.showError(`${file.name} is not a supported image type`)
        return false
      }
      return true
    })

    // Check max files limit
    const remainingSlots = this.maxFiles - this.files.length
    if (validFiles.length > remainingSlots) {
      this.showError(`Maximum ${this.maxFiles} files allowed`)
      validFiles.splice(remainingSlots)
    }

    this.files = this.files.concat(validFiles)
    this.renderPreviews()
    this.updateUploadButton()
  },

  removeFile(index) {
    this.files.splice(index, 1)
    this.renderPreviews()
    this.updateUploadButton()
  },

  renderPreviews() {
    if (!this.previewContainer) return

    this.previewContainer.innerHTML = ""

    this.files.forEach((file, index) => {
      const preview = document.createElement("div")
      preview.className = "relative group"

      const img = document.createElement("img")
      img.className = "w-24 h-24 object-cover rounded border border-gray-200"
      img.alt = file.name

      // Create object URL for preview
      const url = URL.createObjectURL(file)
      img.src = url
      img.onload = () => URL.revokeObjectURL(url)

      const removeBtn = document.createElement("button")
      removeBtn.type = "button"
      removeBtn.className = "absolute -top-2 -right-2 w-5 h-5 bg-red-500 text-white rounded-full text-xs hidden group-hover:block"
      removeBtn.textContent = "×"
      removeBtn.onclick = () => this.removeFile(index)

      const name = document.createElement("div")
      name.className = "text-xs text-gray-600 truncate w-24 mt-1"
      name.textContent = file.name

      preview.appendChild(img)
      preview.appendChild(removeBtn)
      preview.appendChild(name)
      this.previewContainer.appendChild(preview)
    })
  },

  updateUploadButton() {
    if (this.uploadButton) {
      this.uploadButton.disabled = this.files.length === 0
      this.uploadButton.textContent = this.files.length > 0
        ? `Upload ${this.files.length} image${this.files.length > 1 ? "s" : ""}`
        : "Upload Images"
    }
  },

  async uploadFiles() {
    if (this.files.length === 0) return

    // Disable upload button and show progress
    if (this.uploadButton) {
      this.uploadButton.disabled = true
      this.uploadButton.textContent = "Preparing upload..."
    }

    // Request presigned URLs from the server
    const fileInfo = this.files.map(file => ({
      name: file.name,
      type: file.type,
      size: file.size,
      extension: file.name.split(".").pop()
    }))

    this.pushEvent("request_presigned_urls", { files: fileInfo })
  },

  async executeUploads(urls) {
    // urls is an array of { path, presigned_url, content_type }
    this.showProgress()

    const uploadPromises = urls.map((urlInfo, index) => {
      return this.uploadToS3(this.files[index], urlInfo)
    })

    try {
      const results = await Promise.all(uploadPromises)
      const successPaths = results.filter(r => r.success).map(r => r.path)

      if (successPaths.length > 0) {
        // Tell the server which uploads succeeded
        this.pushEvent("uploads_completed", {
          paths: successPaths,
          species_id: this.speciesId
        })
      }

      const failed = results.filter(r => !r.success)
      if (failed.length > 0) {
        this.showError(`${failed.length} upload(s) failed`)
      }
    } catch (error) {
      this.showError("Upload failed: " + error.message)
    }
  },

  async uploadToS3(file, urlInfo) {
    const { path, presigned_url, content_type } = urlInfo

    return new Promise((resolve) => {
      const xhr = new XMLHttpRequest()

      xhr.upload.addEventListener("progress", (e) => {
        if (e.lengthComputable) {
          const percent = Math.round((e.loaded / e.total) * 100)
          this.updateProgress(path, percent)
        }
      })

      xhr.addEventListener("load", () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          this.updateProgress(path, 100)
          resolve({ success: true, path })
        } else {
          resolve({ success: false, path, error: `HTTP ${xhr.status}` })
        }
      })

      xhr.addEventListener("error", () => {
        resolve({ success: false, path, error: "Network error" })
      })

      xhr.open("PUT", presigned_url)
      xhr.setRequestHeader("Content-Type", content_type)
      xhr.send(file)
    })
  },

  showProgress() {
    if (this.progressContainer) {
      this.progressContainer.classList.remove("hidden")
      this.progressContainer.innerHTML = this.files.map((file, i) => `
        <div class="mb-2" data-progress-item="${i}">
          <div class="flex justify-between text-sm mb-1">
            <span class="text-gray-700">${file.name}</span>
            <span class="text-gray-500" data-percent>0%</span>
          </div>
          <div class="w-full bg-gray-200 rounded-full h-2">
            <div class="bg-gf-maroon h-2 rounded-full transition-all duration-200 w-0" data-bar></div>
          </div>
        </div>
      `).join("")
    }
  },

  updateProgress(path, percent) {
    const index = this.files.findIndex(f =>
      path.includes(f.name.split(".").pop())
    )
    if (index === -1) return

    const item = this.progressContainer?.querySelector(`[data-progress-item="${index}"]`)
    if (item) {
      const bar = item.querySelector("[data-bar]")
      const percentEl = item.querySelector("[data-percent]")
      if (bar) bar.style.width = `${percent}%`
      if (percentEl) percentEl.textContent = `${percent}%`
    }
  },

  showSuccess(message) {
    this.showMessage(message, "success")
  },

  showError(message) {
    this.showMessage(message, "error")
  },

  showMessage(message, type) {
    const alertClass = type === "success"
      ? "bg-green-50 border-green-200 text-green-800"
      : "bg-red-50 border-red-200 text-red-800"

    const alert = document.createElement("div")
    alert.className = `p-3 rounded border ${alertClass} mb-4`
    alert.textContent = message

    this.el.insertBefore(alert, this.el.firstChild)

    setTimeout(() => alert.remove(), 5000)
  },

  resetForm() {
    this.files = []
    this.renderPreviews()
    this.updateUploadButton()

    if (this.progressContainer) {
      this.progressContainer.classList.add("hidden")
      this.progressContainer.innerHTML = ""
    }

    // Notify the LiveView to refresh the image list
    this.pushEvent("refresh_images", {})
  }
}

export default ImageUpload
