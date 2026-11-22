---
plan: taxogall
phase: 726a
rank: 200
title: Make file_drop keyboard-operable in both upload hooks
stage: committed
created: "2026-11-22T14:55:39Z"
updated: "2026-11-22T14:55:39Z"
---

Jeff, 2026-11-22 (inbox a485): approved. file_drop (FormComponents) renders a div[data-dropzone] with a hidden file input and no tabindex, role or key handler. Make it focusable and operable (role='button', tabindex='0', Enter and Space open the input) in assets/js/hooks/image_upload.js and content_image_upload.js, with their tests, and update the file_drop entry in docs/design-system/components.md.

Deletes: nothing. Calls: the existing ImageUpload and ContentImageUpload hooks, FormComponents.file_drop.
