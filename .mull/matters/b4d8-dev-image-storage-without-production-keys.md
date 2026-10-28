---
status: raw
created: 2026-10-28
updated: 2026-10-28
epic: platform
---

# Dev image storage without production keys

## Why (2026-10-28)

Development must hold no production credentials. Until today the dev server ran with the `s3-upload` key loaded from `.env` (`make dev` sourced the whole file), so image uploads, deletes and listings from a local server went to the real public images bucket, and that key could also read and write the private bucket. The key has been rotated and removed from the local shell, the private bucket now has a local adapter in dev (`Gallformers.Storage.Private.LocalAdapter`, `tmp/private_storage`), and `make dev` no longer loads `.env`. Image storage is the last piece: without a key, image uploads from a local server now fail.

## Where it is

`Gallformers.Storage.Images` (`lib/gallformers/storage/images.ex`) calls ExAws directly against the images bucket:
- browser uploads via presigned PUT URLs (`presigned_upload_url/2`);
- server uploads (`upload/3`), size variants, deletes, listings;
- public URLs through the CDN (`cdn_url/0`, `public_url/1`).

`S3_IMAGE_PREFIX` already puts preview's new uploads under `preview/`.

## Options

- **A. Local adapter (recommended).** An adapter behaviour for the images module, as for the private bucket: in dev, objects are files under `tmp/images`, served by `Plug.Static`; presigned uploads become a local upload endpoint. No credentials at all. Existing production images still display from the CDN in dev, because their paths resolve to the CDN.
- **B. A dev bucket or prefix with its own IAM user.** It's simpler to build, but it puts a key back into the dev environment, which is what we are removing.

## Done when

- A local server uploads, resizes, displays and deletes images with no AWS credentials.
- Production behaviour is unchanged.
- Tests cover the adapter. The test suite never reaches S3, as now.

