---
kind: decision
text: Curators' browsers upload documents straight to the private bucket through signed URLs for the exact key (as image uploads already do, Storage.Images.presigned_upload_url/2), so large PDFs never pass through the app machine; Storage.Private gains the same function
plan: taxogall
item: 274b
by: /Users/jeff/dev/gallformers
created: "2026-11-22T01:09:39Z"
---

Calls the existing presigned pattern rather than a new upload path
