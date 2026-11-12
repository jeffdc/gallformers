---
title: 'Dev image storage without production keys: a local adapter for Storage.Images'
stage: committed
docs:
  - .mull/matters/b4d8-dev-image-storage-without-production-keys.md
created: "2026-11-09T23:35:21Z"
updated: "2026-11-12T02:23:22Z"
---

Give `Gallformers.Storage.Images` a storage adapter, as the private bucket has, so a local dev server can upload, resize, show and delete images with no AWS credentials.

## Why

Development must hold no production credentials. Until 2026-10-28 the dev server ran with the `s3-upload` key loaded from `.env` (`make dev` sourced the whole file). So image uploads, deletes and listings from a local server went to the real public images bucket, and that key could also read and write the private bucket. Since then:
- the key has been rotated and removed from the local shell;
- `make dev`, `dev-cloudfront` and `dev-lan` no longer load `.env` (a44c9918);
- the private bucket has a local adapter in dev.

Image storage is the last piece. With no key, image uploads from a local server fail.

## Where it is (as of a0434bcf)

`lib/gallformers/storage/images.ex` (`Gallformers.Storage.Images`) builds `ExAws.S3` operations against the images bucket. It runs them through `Gallformers.Storage.S3` (`request/1`, `presigned_url/…`). That wrapper returns canned success when `s3_enabled: false` (test), so tests never reach S3. There is no adapter. What it does:
- **Browser uploads** via presigned PUT URLs: `presigned_upload_url/2`, used by the `ImageUpload` and `ContentImageUpload` hooks.
- **Server uploads:** `upload/3`.
- **Size variants:** `generate_size_variants/2` fetches the original **over HTTP from `public_url/1`** with `Req.get`, resizes it with `Image`, and uploads each variant with `upload/3`. A local adapter must make a just-uploaded original fetchable (or read it from disk).
- **Deletes:** `delete_content_image/2`, `delete_article_image/1`, `delete_keys/1` (`delete_multiple_objects`).
- **Listings:** `list_article_images/0`, `list_article_images_for_article/1` (`list_objects`).
- **Public URLs** through the CDN: `cdn_url/0`, `public_url/1`, `variant_public_url/2`, `article_image_url/1`.
- **The bucket and CDN** come from `config :gallformers, :images` (`config/config.exs`: bucket `gallformers-images-us-east-1`, the CloudFront `cdn_url`, `presign_expiry`).
- **`S3_IMAGE_PREFIX`** (`config/runtime.exs` → `:s3_image_prefix`) already puts preview deploys' new uploads under `preview/`; existing paths still resolve from where they are.
- **Callers:**
  - `lib/gallformers/images.ex`, `lib/gallformers/content_images.ex`, `lib/gallformers/storage.ex`;
  - `admin/images_component.ex` (Gall and taxon photos), `admin/content_image_manager.ex` and `admin/article_live/form.ex` (articles, keys);
  - `key_components.ex`.

**The pattern to follow** is `lib/gallformers/storage/private.ex`. `Gallformers.Storage.Private` delegates to `adapter()`, configured by `config :gallformers, :private_storage, adapter: …`. The default is `Private.S3Adapter`. Dev uses `Private.LocalAdapter` (files under `tmp/private_storage`, gitignored; `config/dev.exs`). Tests use `Gallformers.Storage.PrivateStub` (`config/test.exs`).

## Decided: option A, a local adapter (recommended in the matter)

- An adapter behaviour for the images module, as for the private bucket.
- In dev, objects are files under `tmp/images`, served by `Plug.Static`.
- Presigned uploads become a local upload endpoint.
- No credentials at all.
- Existing production images still display from the CDN in dev, because their paths resolve to the CDN. The matter doesn't say how a path chooses local or CDN (for example a dev path prefix, as `S3_IMAGE_PREFIX` does for preview, or whether the file exists locally). Settle that in the design and test it.

**Rejected: option B,** a dev bucket or prefix with its own IAM user. It is simpler to build, but it puts a key back into the dev environment, which is what this work removes.

## Done when

- A local server uploads, resizes, displays and deletes images with no AWS credentials. That covers browser uploads through the hooks and server uploads such as the iNat import.
- Production behaviour is unchanged: the S3 adapter by default, the same keys, URLs and prefix.
- Tests cover the adapter. The test suite never reaches S3, as now.

From matter b4d8 (option A, recommended; 'Done when' is in the matter). At intake: a44c9918 already removed the production keys from dev, but no adapter exists (lib/gallformers/storage/images.ex calls ExAws directly), so dev image uploads have no backend. Sizing is the intake's guess: if it doesn't fit one session, mull ask to split it.
