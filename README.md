# Passages

Passages is a free Mac app that allows you to read and export highlighted text from Apple Books. You can either export it is a local file or add your highlights to Notion.

## Disclosurs

- Passages is not affiliated with Apple or Notion. It is free and open source under the [MIT license](LICENSE).
- There's no form of tracking, monetization, premium features etc.
- This project serves a simple purpose, and will NOT be actively maintained. If you miss any features or encounter limitations, feel free to tweak the source code to your liking.
- Most of the code was written by AI but I performed a manual review to avoid any critical issues. Nothing is guaranteed though so please do your due diligence.

## Install

1. Download [**Passages.dmg**](https://github.com/HobbieDev24/passages-app/releases/latest/download/Passages.dmg)
2. Open the disk image and drag **Passages** onto **Applications**.

**Current release limitation:** the app has a local signature and is not yet signed with an Apple Developer ID or notarized by Apple. macOS may block a downloaded copy on first launch. After attempting to open it, go to **System Settings → Privacy & Security**, choose **Open Anyway**, and confirm.

## Connect Apple Books

Open Apple Books first and let it finish syncing. In Passages, choose **Allow access**. The app tries the usual Apple Books location and, if permission is needed, opens that folder for you. Click **Allow Access** in the dialog.

Passages remembers this folder permission for future launches. If the connection fails, check that Apple Books has highlights, then choose **Retry**. The app currently supports Apple Books’ standard library location; moved libraries and different storage layouts are not supported.

Once connected, select a book in the sidebar to read its highlights. Search by title or author. Books appear in order of their most recently modified highlight; highlights follow their position in the book. Use the refresh button after making changes in Apple Books.

## Save highlights to files

- **Export Selected Book…** saves the selected book to one file.
- **Export All Books…** asks for a folder and saves one separate file per book.
- You can export highlights as either .md or .txt file, this is configured through the "Settings" menu

## Send highlights to Notion

1. Create an internal connection for your workspace in [Notion’s developer portal](https://www.notion.so/profile/integrations). Give it **Read content** and **Insert content** access.
2. Copy its integration token. In **Passages → Settings → Integrations → Notion**, paste it and choose **Save token**. Passages verifies it before saving it securely in macOS Keychain. If verification fails, it is not saved.
3. In Notion, open your destination page’s **••• → Connections** menu and add your integration.
4. In Passages, select a book, choose **Export to Notion…**, paste the destination page URL, and choose **Export**.

**Every Notion export appends content.** Exporting the same book again creates duplicates; existing content is not replaced.

## Gotchas

- Only books with text highlights appear. Standalone notes, bookmarks, and content that Apple Books does not expose as text highlights may not appear.
- Titles, authors, covers, and chapter names depend on information available locally. Missing information may appear as **Unknown Book**, **Unknown Author**, or a placeholder cover. Opening or downloading the book in Apple Books may help, but does not guarantee complete metadata.
- Apple can change how Books stores its library, any future Apple Books update may be breaking.
- If you want to reset the app -> choose **Passages → Reset Passages…** in the menu bar, then confirm **Reset and Quit**. This removes the saved Notion token, export preferences, Apple Books folder permission bookmark, and macOS privacy permissions for Passages. Reopen the app to see the welcome screen and connect Apple Books again.
