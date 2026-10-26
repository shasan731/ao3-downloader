# User guide

Paste a public AO3 work or series URL (chapter URLs are normalized to their whole work), select **Analyze URL**, review the preview, choose AO3's offered EPUB/PDF/HTML format and a folder, then download. A series preview displays `Part N` beside every title, preserves author order, and provides individual toggles plus All/None controls. For EPUB and PDF, choose **Separate files**, **One combined book**, or **Both**. HTML remains separate-file only. Restricted works must be opened in a browser. The application never asks for an AO3 password.

Analysis and downloads continue when you switch between New Download, Queue, Settings, or other sidebar sections. Queue shows the active phase, elapsed time, processed/total count, current part, and a status icon beside every series part. You may change part selections while downloading: parts not yet started are skipped, and assembly uses the final selection. A green check means its complete official file was downloaded and verified. Because AO3 supplies a whole multi-chapter work as one file, chapter-level network progress is not fabricated; after verification the app displays that work's known chapter count. **Cancel** stops queued or active work and retains/checkpoints already verified files.

## Library, retries, and updates

Every started series becomes a durable Library project. Select it in **Library / History** to see verified, failed, missing-local, and inaccessible parts. Use **Retry** beside a failed part. Once every currently selected part has a green check, **Combine Selected** creates a new EPUB or PDF even if some unselected part failed. Source files are retained for combined-only projects, so recombination does not redownload them.

Change the checkboxes to build an anthology from any verified subset. Edit the title, comma-separated authors, language, and optional JPEG/PNG cover before combining. **Apply Metadata** updates an existing combined book atomically; **Edit Metadata** updates an individual downloaded part; single-work history has **Apply to File**. The original is left intact if validation of an edited replacement fails.

Use **Reanalyze Source** to refresh a saved series. Existing selections and verified files are matched by AO3 work ID, new parts are shown as pending, and **Download Missing Selected** fetches only the selected items not already retained. The format of an existing Library project stays locked because retained source books cannot safely be treated as another format.

