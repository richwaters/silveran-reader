# Changelog

## [0.1-67] -> [0.1-69]

### Features

#### macOS
- M4b creator utility added
- Local readaloud creation utility added (via storyalign)
- Left and right sidebars now expand outwards
- Server media management support for modifying and uploading books (experimental)

### Bug Fixes

- Better multi-series support
- iOS delete buttons made more discoverable
- Chapter and speed menus now scroll to current selection
- Fixes for sync and backgrounding edge cases
- UI elements now check network operation succeeded for status display
- Simplified reconnect, refresh, and phase handling
- Fixed book loading race condition
- Fixed playback of linear audio not in a SMIL entry
- Fixed concurrency issues
- Fixed crashes on long press -> details view
- macOS books view scrolling optimization
- Performance improvements while reading
- Sleep timer fixes
- Fixed incorrect page count on resize

---

## [0.1-58] -> [0.1-67]

### Features

#### General
- New tvOS app available in test flight!
- Overhaul of the highlighting system. Now supports three highlight types: underline, colored text, and colored background (conventional highlight). Four preset themes were added to illustrate these modes.
- Improved series handling with ordering badges and cross links
- Support for rating metadata
- Live sync in player with user prompt on all players (configurable)
- Cover switching between audiobook and ebook covers in player and book details pages
- One-click play on iOS and macOS (configurable)
- Author view now uses row-view of authors
- New views for books by tag and narrator
- Faster navigation with new media overlay manager
- Display multiple narrators and authors

#### iOS
- Made tab bar in Library view show configurable tabs (e.g. collections instead of series)
- Reworked book details view
- Added mini player stats mode (configurable)
- Playback rate slider
- Skip buttons (optionally) available next to overlay stats

#### macOS
- Added resizable second sidebar for certain views

#### tvOS
- Added a new tvOS app. Currently highly barebones and lots of issues, but functional.

#### watchOS
- Added browse by collections

### Bug Fixes

- Lots of work to make things more performant
- Apple watch battery life should be greatly increased during playback
- Optimized network layer (using lightweight endpoint and better condition change detection)
- Fixed a bug on Apple watch where downloads appeared to disappear during saving
- Better handling of long titles on Apple watch via scrolling text
- Fixed a crash on too many covers displayed in fan views
- Progress sync now performed every 3 seconds to match ST clients
- Books in more than one collection now show up in all of them
- Fixed progress sync issues when restoring readaloud from audio
- Fixed progress sync issues when resuming from background
- Apple Watch progress sync now follows other clients (including audio playthrough)
- Settings completely redone
- New robust media overlay playhead handling eliminates race conditions, fixing blank page on chapter switch and flickering between pages during audio playback
- Fixes to EPUB3 TOC navigation
- Fixed some bluetooth headset issues
- Switched to ST readaloud icon for consistency
