# Kindle to Hardcover Sync Scriptlet

A native scriptlet for jailbroken Amazon Kindle e-readers that automatically syncs your current reading progress directly to [Hardcover.app](https://hardcover.app).

## Features
- **No Proxy Needed:** Runs entirely on your Kindle by reading the local `cc.db` SQLite database.
- **Smart Search:** Searches Hardcover's database using the book's ASIN. If that fails (e.g., for side-loaded books), it falls back to a fuzzy search combining the Title and Author.
- **Confidence Check:** If the script isn't 100% confident it found the correct book on Hardcover, it will prompt you on your Kindle's E-ink display to tap to confirm or press the power button to cancel.
- **Native UI:** Uses FBInk to display progress directly on the screen.
- **Auto Wi-Fi:** Automatically turns on Wi-Fi if your Kindle is in airplane mode to perform the sync.

## Prerequisites
1. A **jailbroken Kindle**.
2. **KUAL** and the **Universal Hotfix** (which includes `SH_Integration` for scriptlets) installed.
3. Your Hardcover API Token.

## Installation

1. Generate an API token from your [Hardcover Account Settings](https://hardcover.app/account/api). (Click "Create Token" or "Personal Access Token" to get a long-lived token, do not copy it from your browser's network tab).
2. Download or clone `sync_hardcover.sh`.
3. Create a plain text file named `hardcover_token.txt` on your computer and paste your API token directly inside it (no spaces or extra lines).
4. Connect your Kindle to your computer via USB.
5. Copy both `sync_hardcover.sh` and `hardcover_token.txt` into your Kindle's `/documents` folder (the same place your books go).
6. Eject your Kindle. 

The scriptlet will automatically be indexed and appear in your Kindle Library as a book named "Sync to Hardcover".

## Usage
Simply tap the "Sync to Hardcover" item in your Kindle library when you finish a reading session. It will wake up, read your database, push your progress, and print a confirmation message on your screen.

## Note on Side-loaded Books
For side-loaded books (EPUBs converted to AZW3/KFX), they often lack an ASIN. The script relies on the Title and Author match. To make this 100% reliable, ensure the Title on your Kindle closely matches the Title on Hardcover!
