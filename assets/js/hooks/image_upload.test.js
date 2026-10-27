import { describe, test, expect, beforeEach, vi } from 'vitest'
import { mountHook, getPushedEvents, pushServerEvent } from '../test/hook_test_helper.js'
import ImageUpload from './image_upload.js'

function uploadHTML(opts = {}) {
  const maxFiles = opts.maxFiles || 4
  const speciesId = opts.speciesId || '42'
  return `
    <div data-max-files="${maxFiles}" data-species-id="${speciesId}" data-accepted-types="image/jpeg,image/png">
      <div data-dropzone></div>
      <input data-file-input type="file" multiple />
      <div data-preview-container></div>
      <button data-upload-button disabled>Upload Images</button>
      <div data-progress-container class="hidden"></div>
    </div>
  `
}

function fakeFile(name, type = 'image/jpeg', size = 1024) {
  return new File(['x'.repeat(size)], name, { type })
}

// Stub URL.createObjectURL / revokeObjectURL (jsdom doesn't implement them)
if (typeof URL.createObjectURL !== 'function') {
  URL.createObjectURL = () => 'blob:fake'
  URL.revokeObjectURL = () => {}
}

// ============================================
// File validation and management
// ============================================

describe('ImageUpload file validation', () => {
  let hook

  beforeEach(() => {
    hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()
  })

  test('accepts valid image types', () => {
    hook.addFiles([fakeFile('photo.jpg', 'image/jpeg')])

    expect(hook.files).toHaveLength(1)
  })

  test('rejects non-image files', () => {
    hook.addFiles([fakeFile('doc.pdf', 'application/pdf')])

    expect(hook.files).toHaveLength(0)
    // Should show error message in DOM
    expect(hook.el.textContent).toContain('not a supported image type')
  })

  test('accepts png', () => {
    hook.addFiles([fakeFile('photo.png', 'image/png')])

    expect(hook.files).toHaveLength(1)
  })

  test('enforces max files limit', () => {
    const twoMaxHook = mountHook(ImageUpload, uploadHTML({ maxFiles: 2 }))
    twoMaxHook.mounted()

    twoMaxHook.addFiles([
      fakeFile('a.jpg'),
      fakeFile('b.jpg'),
      fakeFile('c.jpg')
    ])

    expect(twoMaxHook.files).toHaveLength(2)
    expect(twoMaxHook.el.textContent).toContain('Maximum 2 files')
  })

  test('enforces max across multiple adds', () => {
    const twoMaxHook = mountHook(ImageUpload, uploadHTML({ maxFiles: 2 }))
    twoMaxHook.mounted()

    twoMaxHook.addFiles([fakeFile('a.jpg')])
    twoMaxHook.addFiles([fakeFile('b.jpg')])
    twoMaxHook.addFiles([fakeFile('c.jpg')])

    expect(twoMaxHook.files).toHaveLength(2)
  })

  test('mixed valid and invalid files keeps only valid', () => {
    hook.addFiles([
      fakeFile('good.jpg', 'image/jpeg'),
      fakeFile('bad.txt', 'text/plain'),
      fakeFile('also_good.png', 'image/png')
    ])

    expect(hook.files).toHaveLength(2)
  })
})

// ============================================
// File removal
// ============================================

describe('ImageUpload file removal', () => {
  let hook

  beforeEach(() => {
    hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()
    hook.addFiles([fakeFile('a.jpg'), fakeFile('b.jpg'), fakeFile('c.jpg')])
  })

  test('removeFile removes by index', () => {
    hook.removeFile(1) // remove 'b.jpg'

    expect(hook.files).toHaveLength(2)
    expect(hook.files[0].name).toBe('a.jpg')
    expect(hook.files[1].name).toBe('c.jpg')
  })

  test('removeFile updates previews', () => {
    hook.removeFile(0)

    const previews = hook.previewContainer.children
    expect(previews).toHaveLength(2)
  })
})

// ============================================
// Preview rendering
// ============================================

describe('ImageUpload previews', () => {
  test('renders a preview for each file', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    hook.addFiles([fakeFile('a.jpg'), fakeFile('b.jpg')])

    const previews = hook.previewContainer.children
    expect(previews).toHaveLength(2)
    // Each preview should show the filename
    expect(hook.previewContainer.textContent).toContain('a.jpg')
    expect(hook.previewContainer.textContent).toContain('b.jpg')
  })

  test('empty files clears previews', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    hook.addFiles([fakeFile('a.jpg')])
    expect(hook.previewContainer.children).toHaveLength(1)

    hook.removeFile(0)
    expect(hook.previewContainer.children).toHaveLength(0)
  })
})

// ============================================
// Upload button state
// ============================================

describe('ImageUpload button state', () => {
  let hook

  beforeEach(() => {
    hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()
  })

  test('button is disabled with no files', () => {
    expect(hook.uploadButton.disabled).toBe(true)
    expect(hook.uploadButton.textContent).toBe('Upload Images')
  })

  test('button is enabled with files and shows count', () => {
    hook.addFiles([fakeFile('a.jpg')])

    expect(hook.uploadButton.disabled).toBe(false)
    expect(hook.uploadButton.textContent).toBe('Upload 1 image')
  })

  test('button shows plural for multiple files', () => {
    hook.addFiles([fakeFile('a.jpg'), fakeFile('b.jpg')])

    expect(hook.uploadButton.textContent).toBe('Upload 2 images')
  })

  test('removing all files disables button', () => {
    hook.addFiles([fakeFile('a.jpg')])
    hook.removeFile(0)

    expect(hook.uploadButton.disabled).toBe(true)
  })
})

// ============================================
// Upload initiation (server event push)
// ============================================

describe('ImageUpload upload request', () => {
  test('uploadFiles pushes request_presigned_urls with file metadata', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    hook.addFiles([fakeFile('photo.jpg', 'image/jpeg', 2048)])
    hook.uploadFiles()

    const events = getPushedEvents(hook)
    const req = events.find(e => e.event === 'request_presigned_urls')
    expect(req).toBeTruthy()
    expect(req.payload.files).toHaveLength(1)
    expect(req.payload.files[0]).toEqual({
      name: 'photo.jpg',
      type: 'image/jpeg',
      size: 2048,
      extension: 'jpg'
    })
  })

  test('pushes to its own element (its LiveComponent, else the LiveView)', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    hook.addFiles([fakeFile('photo.jpg')])
    hook.uploadFiles()

    const req = getPushedEvents(hook).find(e => e.event === 'request_presigned_urls')
    expect(req.selector).toBe(hook.el)
  })

  test('uploadFiles disables button and shows preparing text', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    hook.addFiles([fakeFile('a.jpg')])
    hook.uploadFiles()

    expect(hook.uploadButton.disabled).toBe(true)
    expect(hook.uploadButton.textContent).toBe('Preparing upload...')
  })

  test('uploadFiles with no files is a no-op', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    hook.uploadFiles()

    expect(getPushedEvents(hook)).toHaveLength(0)
  })
})

// ============================================
// Progress UI
// ============================================

describe('ImageUpload progress', () => {
  test('showProgress creates progress bars for each file', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    hook.addFiles([fakeFile('a.jpg'), fakeFile('b.jpg')])
    hook.showProgress()

    expect(hook.progressContainer.classList.contains('hidden')).toBe(false)
    expect(hook.progressContainer.querySelectorAll('[data-progress-item]')).toHaveLength(2)
    expect(hook.progressContainer.textContent).toContain('a.jpg')
    expect(hook.progressContainer.textContent).toContain('b.jpg')
  })
})

// ============================================
// Server event handlers
// ============================================

describe('ImageUpload completion', () => {
  test('pushes the uploaded paths to its own element', async () => {
    const hook = mountHook(ImageUpload, uploadHTML({ speciesId: '42' }))
    hook.mounted()
    hook.addFiles([fakeFile('a.jpg'), fakeFile('b.jpg')])
    hook.uploadToS3 = async (_file, { path }) => ({ success: path !== 'p2', path })

    await hook.executeUploads([{ path: 'p1' }, { path: 'p2' }])

    const done = getPushedEvents(hook).find(e => e.event === 'uploads_completed')
    expect(done.selector).toBe(hook.el)
    expect(done.payload).toEqual({ paths: ['p1'], species_id: '42' })
    expect(hook.el.textContent).toContain('1 upload(s) failed')
  })
})

describe('ImageUpload server events', () => {
  test('upload_complete resets form and pushes refresh_images', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    hook.addFiles([fakeFile('a.jpg')])
    expect(hook.files).toHaveLength(1)

    pushServerEvent(hook, 'upload_complete', { message: 'Done!' })

    expect(hook.files).toHaveLength(0)
    expect(hook.uploadButton.disabled).toBe(true)
    const refresh = getPushedEvents(hook).find(e => e.event === 'refresh_images')
    expect(refresh.selector).toBe(hook.el)
  })

  test('upload_error shows error message', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    pushServerEvent(hook, 'upload_error', { message: 'Something went wrong' })

    expect(hook.el.textContent).toContain('Something went wrong')
  })
})

// ============================================
// Drag and drop
// ============================================

describe('ImageUpload drag and drop', () => {
  test('dragover adds highlight classes', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    const event = new Event('dragover', { bubbles: true, cancelable: true })
    event.preventDefault = vi.fn()
    event.stopPropagation = vi.fn()
    hook.dropzone.dispatchEvent(event)

    expect(hook.dropzone.classList.contains('border-gf-maroon')).toBe(true)
  })

  test('dragleave removes highlight classes', () => {
    const hook = mountHook(ImageUpload, uploadHTML())
    hook.mounted()

    // Simulate dragover then dragleave
    const over = new Event('dragover', { bubbles: true, cancelable: true })
    over.preventDefault = vi.fn()
    over.stopPropagation = vi.fn()
    hook.dropzone.dispatchEvent(over)

    const leave = new Event('dragleave', { bubbles: true, cancelable: true })
    leave.preventDefault = vi.fn()
    leave.stopPropagation = vi.fn()
    hook.dropzone.dispatchEvent(leave)

    expect(hook.dropzone.classList.contains('border-gf-maroon')).toBe(false)
  })
})
