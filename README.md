# Hardcover Sync for Kindle (KUAL Extension)

A native application for jailbroken Amazon Kindle e-readers that automatically syncs your current reading progress, ratings, and read dates directly to [Hardcover.app](https://hardcover.app).

## Features
- **Auto-Sync Daemon:** Runs silently in the background. When you open a new book, it asks if you want to track it. When you close a book, it automatically pushes your progress to Hardcover over Wi-Fi.
- **Smart Local Caching:** Remembers book IDs locally so it only has to search the Hardcover database once per book.
- **Star Ratings:** When you reach 100% in a book, a native Kindle pop-up asks you to give it a 1-5 star rating before syncing.
- **No Proxy Needed:** Runs entirely on your Kindle by reading the local `cc.db` SQLite database.

## Prerequisites
1. A **jailbroken Kindle**.
2. **KUAL** (Kindle Unified Application Launcher) installed.
3. Your Hardcover API Token.

## Installation

1. Generate an API token from your [Hardcover Account Settings](https://hardcover.app/account/api). (Click "Create Token" or "Personal Access Token" to get a long-lived token, do not copy it from your browser's network tab).
2. Download this entire repository as a ZIP file and extract it.
3. Create a plain text file named `hardcover_token.txt` and paste your API token directly inside it (no spaces or extra lines).
4. Place `hardcover_token.txt` inside the extracted `kindle-hardcover-sync` folder.
5. Connect your Kindle to your computer via USB.
6. Copy the entire `kindle-hardcover-sync` folder into the **`extensions`** folder on your Kindle drive (`/mnt/us/extensions/`).
7. **(Optional) Scriptlet Installation:** If you want to manually sync from your Kindle Library without opening KUAL, copy the `Sync_to_Hardcover.sh` file from the `scriptlet` folder into your Kindle's **`documents`** folder (`/mnt/us/documents/`).
8. Eject your Kindle. 

## Usage
Open **KUAL** on your Kindle. You will see a new menu item called **Hardcover Sync**.

*   **Sync Current Book Now:** Manually forces a sync of the last book you opened.
*   **Auto-Sync Settings:** 
    *   **Start Daemon:** Enables the background listener. It will prompt you to track new books when opened, and automatically sync progress when closed.
    *   **Stop Daemon:** Disables background syncing.
*   **Clear Hardcover Book Cache:** Wipes the local memory of matched books, forcing the script to re-search Hardcover the next time you sync.

**Library Syncing (Scriptlet):** If you installed the optional Scriptlet in Step 7, an item named "Sync to Hardcover" will appear directly in your Kindle library. Simply tap it to manually sync your current book at any time.

## Note on Side-loaded Books
For side-loaded books (EPUBs converted to AZW3/KFX), they often lack an ASIN. The script relies on the Title and Author match. If the auto-matcher fails, it will ask you to confirm if it found the right book.
