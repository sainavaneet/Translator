## Translator (macOS menu bar app)

A simple macOS **menu bar translator**:

- Copy text → it automatically translates it to your selected **Target Language**
- Optional: automatically copies the **translated text back to your clipboard**

This is an Xcode project written in Swift.

## Features

- **Menu bar UI** with current target language
- **Target language picker** (English, Spanish, Korean, Vietnamese, Japanese, German, French)
- **Auto-copy translation** toggle (menu item + `A` button in the menu bar pill)
- **Pause / Resume** toggle (menu item + `P` button in the menu bar pill)
- **Translation history** (recent items in the menu)

## How it works

- The app polls your clipboard at a short interval.
- When it sees new text, it detects the source language and translates to your selected target language.
- If **Auto-copy Translation** is enabled, the translated result is written back to the clipboard.

Translations are fetched via Google Translate’s public endpoint (`translate.googleapis.com`).

## Requirements

- macOS
- Xcode (to build/run from source)

## Run from Xcode

1. Open `Translator.xcodeproj` in Xcode
2. Select the `Translator` scheme
3. Press **Run** (⌘R)

The app appears in the macOS menu bar.

## Usage

- **Pick a target language**: menu bar icon → **Target Language** → select a language
- **Toggle auto-copy**:
  - menu bar icon → **Auto-copy Translation** (or press `a`)
  - or click the **A** button inside the menu bar pill
- **Pause / Resume**:
  - menu bar icon → **Pause / Resume** (or press `p`)
  - or click the **P** button inside the menu bar pill

## Install to /Applications (optional)

This repo includes `copy_to_applications.sh`, which copies the built `Translator.app` into `/Applications`.

One common setup is to add it as an Xcode **Run Script Build Phase** (so it installs after building).

## Troubleshooting

- **Nothing happens when I copy text**
  - Make sure the app is not **Paused**
  - Make sure the copied text is not extremely long (there is a max length limit)
- **Translation fails**
  - Check your internet connection / DNS

## Notes / Privacy

- The copied text is sent to Google Translate to perform translation.
- Don’t use it for sensitive/private text unless you’re comfortable with that.

