# Recently Opened Settings Requirements

## Purpose

Give users control over whether recently opened PDFs are displayed and
remembered, while keeping the default experience convenient.

## Settings

### Show Recently Opened

- [ ] Add a **Show Recently Opened** toggle in Settings.
- [ ] Enable the toggle by default.
- [ ] When enabled, display the Recently Opened section in the library.
- [ ] When disabled, hide the section without deleting its history.
- [ ] Apply and save the change immediately without requiring a Done button.
- [ ] Preserve this preference after the application restarts.

### Maximum Recent Files

- [ ] Add a **Maximum Recent Files** setting.
- [ ] Provide limits of 5, 10, and 20 files.
- [ ] Use 10 files as the default limit.
- [ ] Apply a changed limit immediately.
- [ ] Remove the oldest entries when the stored history exceeds the selected
      limit.
- [ ] Preserve the selected limit after the application restarts.

### Remember Recent Files

- [ ] Add a **Remember Recent Files** privacy toggle.
- [ ] Enable the toggle by default.
- [ ] When enabled, record a PDF after it is successfully opened.
- [ ] When disabled, stop recording newly opened PDFs.
- [ ] Ask for confirmation before clearing existing history when this setting
      is disabled.
- [ ] If the user cancels the confirmation, leave the setting and history
      unchanged.
- [ ] If the user confirms, disable tracking and clear the existing history.
- [ ] Preserve this preference after the application restarts.

### Clear Recent History

- [ ] Add a **Clear Recent History** action in Settings.
- [ ] Ask for confirmation before clearing history.
- [ ] Disable the action or show an appropriate empty-state message when no
      history exists.
- [ ] Update the library immediately after history is cleared.
- [ ] Do not delete any PDF files when clearing history.

## Recently Opened Behavior

- [ ] List the most recently opened PDF first.
- [ ] Keep only one entry per PDF, even when it is opened multiple times.
- [ ] Move an existing entry to the first position when that PDF is reopened.
- [ ] Record an item only after the PDF opens successfully.
- [ ] Do not create a recent entry when opening fails or is cancelled.
- [ ] Remove an entry when its PDF is deleted from the device through
      Papertrail PDF.
- [ ] Update the entry when its PDF is renamed or moved through Papertrail
      PDF.
- [ ] Remove or clearly mark entries whose files are no longer accessible.
- [ ] Support PDFs opened from the library, Android Open with, the Share menu,
      deep links, and supported iOS document-provider flows.
- [ ] Keep recent-history updates consistent when the application is closed
      unexpectedly.

## User Interface

- [ ] Place these controls in a collapsible **Recently Opened** group in
      Settings.
- [ ] Add suitable icons to the group and its actions.
- [ ] Clearly show the selected maximum-file limit.
- [ ] Use accessible labels for toggles, values, confirmation dialogs, and
      actions.
- [ ] Hide the library section completely when **Show Recently Opened** is
      disabled.
- [ ] Display a useful empty state when the section is enabled but has no
      entries.
- [ ] Indicate horizontally scrollable content when additional recent files
      exist outside the visible area.

## Privacy and Storage

- [ ] Store only the information required to identify and display recent PDFs.
- [ ] Keep recent-history data on the device.
- [ ] Do not upload recent-history data.
- [ ] Do not expose sensitive file paths unnecessarily in the interface,
      diagnostics, or crash reports.
- [ ] Ensure clearing application data also clears recent-history preferences
      and records.

## Acceptance Criteria

- [ ] Recently Opened is visible and tracking is enabled on a new
      installation.
- [ ] Hiding the section does not erase its entries.
- [ ] Showing the section again restores the retained entries.
- [ ] Disabling history tracking requires confirmation before existing
      entries are erased.
- [ ] No new entries are recorded while history tracking is disabled.
- [ ] Re-enabling history tracking records only PDFs opened afterward.
- [ ] Reopening a PDF does not create a duplicate entry.
- [ ] The configured 5, 10, or 20-item limit is enforced.
- [ ] Deleted, renamed, and moved PDFs are handled correctly.
- [ ] All settings survive an application restart.
- [ ] Unit, widget, and integration tests cover the settings and behaviors
      defined in this document.

