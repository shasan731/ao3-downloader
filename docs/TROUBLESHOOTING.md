# Troubleshooting

## macOS says the app is damaged or cannot be opened

Use the DMG from the [official repository release](https://github.com/shasan731/ao3-downloader/releases/latest), verify `SHA256SUMS.txt`, and move ArchiveBind to Applications before launching it. Current community builds are ad-hoc signed but not Apple-notarized. After the first blocked attempt, open **System Settings → Privacy & Security**, scroll to Security, and choose **Open Anyway** only if the checksum matches and you trust this repository.

Do not disable Gatekeeper globally. Re-download the release if the checksum does not match.

## Analysis or download appears slow

ArchiveBind deliberately serializes all AO3 requests and waits at least the configured interval. AO3 may request a longer cooldown. The **Activity** section shows the current stage and elapsed time; switching sections does not stop the task.

## A series part failed

Open the saved project in **Library** and read the failure beneath that part. Resolve content-warning consent or connectivity issues, then select **Retry**. Successfully verified parts remain available. Once every selected part is verified, use **Combine Selected** even if an unselected part still failed.

## A downloaded part is missing locally

Library marks moved or deleted source files as missing. Re-select and download that part before combining. Moving the entire project folder may prevent a saved security-scoped location from resolving; reveal the folder from Library before reorganizing its contents.

## A series has new parts

Open it in Library and choose **Reanalyze Source** from the ellipsis menu. Existing work IDs, selections, and verified files are preserved; new parts appear for selection and missing-only download.

## Reporting a problem

Use the repository’s bug report form. Include the app version, macOS version, operation stage, and sanitized error text. Never attach downloaded story contents, cookies, credentials, or sensitive URL query strings.
