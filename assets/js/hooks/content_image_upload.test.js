import { describe, test, expect } from 'vitest'
import { mountHook, getPushedEvents, pushServerEvent } from '../test/hook_test_helper.js'
import ContentImageUpload from './content_image_upload.js'

function uploadHTML() {
  return `
    <div data-owner-type="article" data-owner-id="7" data-max-files="10" data-accepted-types="image/jpeg,image/png">
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

// The handlers live in the ContentImageManager LiveComponent, not in the
// article/key LiveViews, so every event must go to the hook's own element.
describe('ContentImageUpload events go to its own element', () => {
  test('request_presigned_urls', () => {
    const hook = mountHook(ContentImageUpload, uploadHTML())
    hook.mounted()

    hook.addFiles([fakeFile('photo.jpg')])
    hook.uploadFiles()

    const req = getPushedEvents(hook).find(e => e.event === 'request_presigned_urls')
    expect(req.selector).toBe(hook.el)
    expect(req.payload.files).toEqual([
      { name: 'photo.jpg', type: 'image/jpeg', size: 1024, extension: 'jpg' }
    ])
  })

  test('uploads_completed carries only the successful paths', async () => {
    const hook = mountHook(ContentImageUpload, uploadHTML())
    hook.mounted()
    hook.addFiles([fakeFile('a.jpg'), fakeFile('b.jpg')])
    hook.uploadToS3 = async (_file, { path }) => ({ success: path !== 'p2', path })

    await hook.executeUploads([{ path: 'p1' }, { path: 'p2' }])

    const done = getPushedEvents(hook).find(e => e.event === 'uploads_completed')
    expect(done.selector).toBe(hook.el)
    expect(done.payload).toEqual({ paths: ['p1'] })
    expect(hook.el.textContent).toContain('1 upload(s) failed')
  })

  test('refresh_images after upload_complete', () => {
    const hook = mountHook(ContentImageUpload, uploadHTML())
    hook.mounted()
    hook.addFiles([fakeFile('photo.jpg')])

    pushServerEvent(hook, 'upload_complete', { message: '1 image(s) uploaded successfully' })

    expect(hook.files).toHaveLength(0)
    const refresh = getPushedEvents(hook).find(e => e.event === 'refresh_images')
    expect(refresh.selector).toBe(hook.el)
  })
})
