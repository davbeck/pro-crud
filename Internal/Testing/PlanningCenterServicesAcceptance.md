# Planning Center Services to ProPresenter acceptance

Verified November 8, 2026 against the authorized test church and the local
ProPresenter 22 beta, build `369098875`, at `/Applications/ProPresenter.app`.
This is contributor acceptance evidence, not an automated rendering reference.

## Tested path

1. Create a uniquely named, media-free, 1920 × 1080 target-22 `.pro` with
   `pro-crud create presentation`. Apply the bundled Classic Worship `Medium`
   template and set its editable Lyrics element to:

   ```text
   Planning Center → ProPresenter
   End-to-end import verified
   ```

2. In the test church, create a disposable Services song and use its default
   arrangement. Upload the actual `.pro` with:

   ```sh
   pro-crud planning-center attachments upload PRESENTATION.pro \
     --song SONG_ID --arrangement ARRANGEMENT_ID
   ```

3. Add that song and arrangement to the test plan's order of service. The test
   scaffold used the public Services API's plan-item creation endpoint with
   explicit `song_id` and `arrangement_id`; this is separate from the CLI's
   attachment upload.
4. In ProPresenter's Planning Center settings, verify the same test church,
   **Automatically Download Presentations and Media**, and **Download Library**.
   The tested host already had download, upload, library matching, sequence
   arrangements, and update checking enabled; these settings were not changed.
   The download library was **Default**.
5. Refresh the already imported Planning Center playlist. No local file import,
   drag-and-drop attachment selection, or manual presentation linking was used.
   The unique presentation was not in the local library before this refresh.

## Observed result

- The plan changed from zero items to one linked presentation. ProPresenter
  downloaded the `.pro` and added it to the configured library automatically.
- The library copy was named `ProCRUD-PCO-E2E-20261108`, matching the uploaded
  filename's stem. The Planning Center item retained the song title
  `ProCRUD PCO End-to-End 20261108`.
- Its slide thumbnail and triggered output preview displayed both expected lines.
- **File → Export → Presentation** exported the imported copy as a `.pro` that
  passed `pro-crud validate`. Comparing semantic dumps with the uploaded source
  confirmed exact editable text, text-element UUID, and text-element bounds:
  `x=190, y=250, width=1540, height=580`.
- **File → Export → Slide Images**, JPEG with slide background color, produced
  one 1920 × 1080 image. Visual inspection confirmed both lines, the arrow glyph,
  centered layout, white text, and black background without clipping.
- `snap-syphon list --json` returned no published sources on this host despite
  stored Syphon screen bindings. Render evidence therefore consists of the
  native output preview and native slide-image export, not a Syphon capture.
  No screen output was added or rebound.

Local diagnostic artifacts from this run were saved under
`/tmp/pro-crud-pco-native-export` and `/tmp/pro-crud-pco-e2e-live.png`. They are
not checked-in fixture references or bundled skill assets.

## Cleanup and scope

The disposable remote plan item and song were removed. Refreshing ProPresenter
returned the existing plan to zero items. The downloaded test presentation was
then removed from the Default library through ProPresenter, and the test slide
was cleared from output. The pre-existing plan, libraries, presentations, and
screen configuration were retained.

This qualifies the CLI upload → Services arrangement attachment → native
ProPresenter automatic download/link → editable presentation/render path for
this media-free target-22 sample on this build. It does not qualify background
media synchronization, overwriting an already linked local presentation,
multiple compatible attachment selection, other app versions, or unattended
plan updates without applying a refresh.
