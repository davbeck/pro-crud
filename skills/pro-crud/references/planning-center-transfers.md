# Planning Center presentation and media transfers

Use this workflow when delivering prepared presentations through Planning Center
Services to ProPresenter. ProPresenter's Planning Center integration transfers
individual `.pro` presentation attachments and standalone media cues. Its
documented workflow does not synchronize media inside presentations, including
slide backgrounds.

## Attach a `.pro` for a song

1. Prepare and validate the individual `.pro` presentation. If the source is a
   `.probundle`, expand it and select the intended `.pro` payload; renaming the
   archive does not convert it into a presentation.
2. In Services, open **Songs → the song → the arrangement used in the plan →
   Files → +** and upload the actual `.pro` file. Attach it to the arrangement
   for availability in every key, or to a specific key when intentionally limited
   to that key. For example, attach `Amazing Grace.pro` to the scheduled
   arrangement's Files, available for all keys.
3. Add that song to the plan's order of service with the matching arrangement
   and, for key-specific attachments, the matching key. You can also open the
   song in the plan and use **Files → Add files to linked song**.
4. In ProPresenter, sign into Planning Center under **Settings → Integrations**,
   enable **Automatically Download Presentations and Media**, and choose the
   **Download Library**. Import the plan using **+ → Planning Center Service**
   beside the library/playlist list. Downloaded presentations are added to that
   library and linked to the corresponding playlist items.
5. Verify that the intended presentation is linked. If it is not, use the item's
   **Add an attachment from Planning Center** control to open the Attachment
   Manager and drag the intended attachment onto the item. If another local
   presentation is already linked, unlink it before selecting the replacement.

Attach the file to the song/arrangement used by the plan. A general plan-level
attachment is a separate location; placing a `.pro` there does not establish
the item attachment association needed by this workflow. Uploading a file
somewhere in Services also does not import its plan into ProPresenter.

For standalone images or videos, attach the file to a Services **Media** item
and schedule that item in the plan. Do not assume a `.pro` attached to a Media
item follows the song-presentation auto-download rule. For sermon or announcement
presentations, verify attachment availability and linking in ProPresenter's
Attachment Manager, or import the presentation locally and link it to the
appropriate plan item.

## Transfer controls and selection

- **Upload to Planning Center Services** on a linked playlist item manually
  uploads its linked presentation or standalone media to the corresponding
  Services item. **Automatically Upload Presentations and Media** automates
  that attachment upload for linked items in Planning Center playlists.
- **Automatically Download Presentations and Media** selects a ProPresenter
  presentation attachment for a song item and a media attachment for a media
  item. It does not download every attachment or scan the entire Services
  account. Keep one intended compatible attachment per item when practical;
  Renewed Vision's guides describe selection as both the first attachment and
  the most recent attachment. Do not depend on ordering to select a version.
- **Automatically Check for Plan Updates** detects changes, including compatible
  new attachments. Apply **Update Available** when offered, or check manually;
  this setting does not guarantee immediate replacement of already linked slides.
- **Match Presentations in Library** can link an existing local presentation by
  title or CCLI number. Check the linked content rather than assuming a newly
  uploaded attachment replaced a local match.
- **Make Arrangements from Sequences** creates ProPresenter arrangements from
  Services song sequences; it does not transfer presentation files or media.
- Unlinking in ProPresenter leaves the remote attachment in Services. Linking
  another presentation with automatic upload enabled can add another attachment.
  Review existing attachments before uploading a replacement.

## Bundles and slide media

The documented upload uses `.pro` files, not `.probundle` archives. Automatic
download, unpacking, and linking of `.probundle` attachments is undocumented;
do not promise it. For a bundle delivery, download the `.probundle`, import it
into ProPresenter, and link the imported presentation to its playlist item.

A `.pro` transfer does not carry its referenced backgrounds or other slide media.
Provide those assets on the receiving computer and verify media resolution, or
use the manual bundle import workflow. A separately transferred media cue does
not automatically become a background inside a downloaded presentation.

These instructions describe ProPresenter's Services integration. The local
playlist link/unlink operations in this skill do not upload files, associate
remote attachments, refresh plans, or run the integration's downloads.

## Official references

- [Renewed Vision: Using Planning Center with ProPresenter](https://support.renewedvision.com/hc/en-us/articles/4408670102419-Using-Planning-Center-with-ProPresenter)
- [Renewed Vision: Adding a Planning Center Plan to ProPresenter](https://support.renewedvision.com/hc/en-us/articles/360062310714-Adding-a-Planning-Center-Plan-to-ProPresenter)
- [Renewed Vision: Planning Center Online Preferences](https://support.renewedvision.com/hc/en-us/articles/1500003710301-Planning-Center-Online-Preferences)
- [Planning Center: Add files to a song](https://help.planningcenter.com/en/139434-add-files-to-a-song.html)
- [Planning Center: Create, upload, or link to files](https://help.planningcenter.com/en/139415-create%2C-upload%2C-or-link-to-files.html)
- [Planning Center: Edit a song from a plan](https://help.planningcenter.com/en/139433-edit-a-song-from-a-plan.html)
- [Planning Center: Set up the service order](https://help.planningcenter.com/en/139467-set-up-the-service-order.html)
