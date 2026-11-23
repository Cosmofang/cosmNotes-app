# cosmNotes

[中文](README.md) | **English**

A lightweight macOS sticky notes app built with Swift and SwiftUI, with zero third-party dependencies.

cosmNotes is an independent iteration of StickyNotes v2.2.0 by simony3, credited in the app as “StickyNotes 大神的迭代版”. The repository and app bundle include the original MIT license and copyright notice. [StickyNotes v2.2.0](https://github.com/simony3/StickyNotes/tree/v2.2.0)

## Screenshots

<table>
  <tr>
    <td align="center"><b>📝 Text Notes</b><br><sub>Markdown rendering · Glassmorphism</sub></td>
    <td align="center"><b>✅ Todo Notes</b><br><sub>Check to strike through</sub></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/note-text.png" width="330" alt="Text note: Markdown preview"></td>
    <td><img src="docs/screenshots/note-todo.png" width="310" alt="Todo note"></td>
  </tr>
</table>

<b>🕰 History</b> — deleted notes are archived by date, so you can look back at what you did each day and restore any note with one click<br>
<img src="docs/screenshots/history.png" width="480" alt="History: grouped by date">

<br><b>📏 Collapsed Notes + Edge Snapping</b> — collapse a note into a single title bar (todo notes show completion progress);
drag it near the left/right screen edge to snap flush, with the edge-side corners "cut flat"; release to settle smoothly with trackpad haptic feedback<br>
<img src="docs/screenshots/capsule-todo-snapped.png" width="190" alt="Todo capsule snapped to left edge with 2/4 progress, flat left end"><br>
<img src="docs/screenshots/capsule-text-snapped.png" width="112" alt="Text note capsule snapped to left edge"><br>
<img src="docs/screenshots/capsule-free.png" width="135" alt="Free-floating capsule with rounded ends">

## Features

- **Two note types**
  - 📝 **Text notes**: Markdown support (headings, lists, todo syntax, quotes, bold/italic/inline code, dividers), one-click toggle between edit and preview
  - ✅ **Todo notes**: add items one by one, check the box to strike through, edit or delete individual items
- **Three window modes** (set per note)
  - 📌 Always on top — floats above every other window
  - 🪟 Normal window — behaves like a regular app
  - 🖥 Pinned to desktop — sinks to the desktop layer, sticking to the wallpaper like a widget without blocking anything
- **History**: deleted notes are automatically archived by date; browse day by day and restore with one click
- **Collapsed notes**: collapse a note into a single title bar — the title comes from the first line and is never truncated; todo notes show completion progress (e.g. `2/4`); collapsed state persists across restarts
- **Edge snapping**: drag a collapsed bar near the left/right screen edge to snap flush — the edge-side corners turn square (as if "cut off" by the screen), with trackpad haptic feedback; release to settle smoothly
- **Checkable preview**: in text-note preview mode, the checkboxes rendered from `- [ ]` are directly clickable, and the source text stays in sync
- **Highlighter**: drag across text to mark it just like a real highlighter — works in both text and todo notes; backspace erases character by character, the highlight color matches each note's theme, and highlights persist, follow your edits, and stay visible in preview mode
- **AI integration (MCP)**: built-in MCP server so AI assistants like Codex / Claude can create, edit, delete, move, collapse, and restore notes directly (see below)
- **Five soft colors**: Morandi-style lemon yellow / peach pink / mint green / sky blue / lilac purple
- **Glassmorphism design**: frosted translucent background, gradient glass border, serif headings
- **Auto save**: writes to disk 1 second after you stop typing; position, size, color, and mode are all remembered
- **Launch at login**: one-click toggle in the menu bar
- **Unobtrusive**: no Dock icon — lives quietly in the menu bar; borderless rounded-card design

## Install

Requires macOS 14 or later. Download and unzip the archive, then drag `cosmNotes.app` to Applications. The archive supports Apple Silicon and Intel Macs and uses an ad-hoc signature. [Download the latest version](https://github.com/Cosmofang/cosmNotes-app/releases/latest)

You can also build from source after installing Xcode Command Line Tools with `xcode-select --install`.

```bash
git clone https://github.com/Cosmofang/cosmNotes-app.git
cd cosmNotes-app
./build.sh
```

`build.sh` produces an ad-hoc signed app at `build/cosmNotes.app`.

### Updates

cosmNotes checks GitHub Releases at launch and every four hours while it runs. The menu bar shows when a new version is available. Use Check for Updates to check immediately. Choose Download Update to get the ZIP. Unzip it, quit the current app, and drag the new app into Applications to update.

## Usage

Expand the Work Timeline and click anywhere on the sun and moon switch in the upper right to toggle between light and dark appearances. Notes, the calendar, and forms switch together, and the app remembers your choice after relaunch. Native Liquid Glass controls are available on macOS 26 and later.

### Work Timeline

Open Work Timeline or New Work from the menu bar. Each work item needs a title and a due date. The overview is optional.

The Work Timeline opens as a normal window by default. Use the pin in the title bar to toggle always-on-top mode. The app remembers this setting. Use the arrow to collapse or expand the timeline.

The timeline calendar uses project colors for deadlines. One day appears as a dot, and consecutive dates for the same project form a line. Use the button in the month header to collapse the calendar. Browse by month and click a day to filter the list. Use All Dates to clear the filter. In the work editor, click the due date to open the calendar picker.

Drag the handle beside the month heading down to place the calendar below the project list, or up to move it back above. The app remembers its position.

Drag an edge or corner of the expanded window to resize it. The timeline remembers that size after folding or reopening the app.

Project chips fit their names and wrap onto new lines. Click the pencil beside a project to edit its name and color. Drag a work title onto a project to assign it, or onto Unassigned to remove the assignment. Click a project to see its work. The new-work and edit forms also have a project picker.

All Work shows a project tree. Drag the handle on the right of a project row up or down. Nearby rows make room, and the dashed outline shows where the project will land. The app saves the order and updates the project chips above. Click a project row to expand or collapse its work independently. When all projects are collapsed, use Add Project at the bottom of the list to create a project. When a project is expanded or viewed on its own, Add Work at the bottom of its list opens the form with that project selected. New Work at the bottom of the Unassigned list opens the form with Unassigned selected.

Click a work title to expand or collapse its overview below. Existing notes appear in the overview. Use Add Overview or the item's pencil button to enter or edit the text.

Click the pin beside an item to move it to the Pinned section at the top. Click it again to return the item to its date group. By default, pending work is ordered by due date within each section. Completed work moves to Completed. Reopening a previously pinned item returns it to Pinned.

Drag the handle on the right of a work item to reorder it within the same section of its project. The app saves the order for the next launch.

### Sticky Notes

| Action | How |
|---|---|
| New note | Menu bar 📝 icon, or **+** in a note's top bar (both let you pick the type) |
| Move | Drag anywhere on the note |
| Resize | Drag the note's edges. To-do notes size themselves to their content by default (wide enough for the longest item on one line, wrapping past 360pt); a dimension you drag stays as you set it, and right-click → "恢复自动适配大小" restores auto-fit |
| Change color / window mode | Hover over the note's top bar (on narrow notes these fold into the "···" menu) |
| Edit / preview | ✏️ / 👁 button in the top bar |
| Collapse / expand | Collapse button at the far right of the top bar |
| Edge snap | Drag a collapsed bar near the left/right screen edge (snaps within 16pt, drag away to release) |
| Check off todos | Click the checkbox in a todo note; clicking `- [ ]` boxes in text-note preview works too |
| Highlighter | Top-bar highlighter button or `⌘⇧H` to enter the mode: drag to paint, click to place the caret, backspace to erase, Esc to exit; the right-click menu erases the selection or clears all highlights |
| Delete note | ✕ at the top left (archived into history, recoverable) |
| View / restore history | Menu bar → "History" |
| Summon all notes | Click the app icon |

### Markdown cheat sheet (text notes)

```markdown
# H1   ## H2   ### H3
- bullet list
- [ ] todo   - [x] done
> quote
**bold** *italic* `code`
---
```

## AI Integration (MCP)

The app includes an MCP server that uses the Python 3 standard library. After connecting Codex, try “Add Draft weekly report to cosmNotes, due on 2026-11-20.” Once the app saves the item, the tool returns its title, due date, and ID. [MCP](https://modelcontextprotocol.io/)

**Available tools:**

| Tool | Description |
|---|---|
| `create_work` | Add a work item with a `title` and `due_date` (`YYYY-MM-DD`). Use optional `notes` for the overview. |
| `create_note` | Create a note (full parameters: type / color / window mode / collapsed, plus words to highlight or bold) |
| `update_note` | Change content, color, window mode, preview, or collapsed state by id — and reset highlight/bold marks |
| `delete_note` | Delete a note (non-empty content is archived automatically) |
| `move_resize_note` | Move or resize a note window (setting a to-do note's width/height turns off auto-fit for that dimension) |
| `list_notes` / `list_history` | Read active notes and history, including ids needed by other tools |
| `restore_note` | Restore an archived item as a note |
| `delete_history_item` | Permanently delete one history item |
| `show_all_notes` / `show_history` | Bring notes forward or open the history window |

Marks are specified by text, not offsets: `highlight: ["key point"]` paints every occurrence of "key point" in the note, and `bold` works the same way; pass `[]` to clear. When `update_note` only replaces the text, existing highlights and bold runs are re-anchored by the words they covered, so an AI rewording one sentence doesn't wipe them all.

cosmNotes receives and saves everyday changes. For bulk migration or recovery, set `COSMNOTES_ENABLE_ADMIN_TOOLS=1` in the MCP process environment to enable `admin_export_data` and `admin_overwrite_data`. An overwrite also requires the current data revision and explicit confirmation.

For Codex desktop, add the following to `~/.codex/config.toml`.

```toml
[mcp_servers.cosmnotes]
command = "python3"
args = ["/Applications/cosmNotes.app/Contents/Resources/mcp/cosmnotes_mcp.py"]
```

To register the MCP server in Claude Code, run the following command.

```bash
claude mcp add cosmnotes -- python3 /Applications/cosmNotes.app/Contents/Resources/mcp/cosmnotes_mcp.py
```

Restart the client and the AI will see the tools above.

## Data Storage

Active notes, history, work, and projects are stored as plain JSON in `notes.json`, `history.json`, `work-items.json`, and `work-projects.json` under `~/Library/Application Support/cosmNotes/`.

For isolated tests, quit the running copy of cosmNotes and set the same `COSMNOTES_DATA_DIR` for the app and MCP process before launching. When running the MCP script from source, set `COSMNOTES_APP_PATH` to point to a test app bundle.

## Project Structure

```
Sources/StickyNotes/
├── main.swift          # Entry point, NSApplication startup, hidden Edit menu (keyboard shortcuts)
├── AppIdentity.swift   # App identity, preferences, and data directory
├── AppDelegate.swift   # Menu bar, note window management, type picker, URL interface
├── Note.swift          # Data model + JSON persistence + todo item I/O + history archiving
├── NoteView.swift      # SwiftUI views: note view, todo list, Markdown rendering, capsule bar
├── HistoryView.swift   # History window: grouped by date, restore, permanent delete
├── WorkTimeline.swift  # Floating timeline and editor
└── NoteWindow.swift    # Borderless window, three layer modes, collapse & edge snapping
Sources/CosmNotesWork/  # Work storage, calendar rules, and local requests
mcp/
└── cosmnotes_mcp.py    # MCP server: entry point for AI clients to control notes
```

## Contribute

Create a branch from `main` and submit a pull request. If you need write access for your branch, fork the repository and submit from the fork. GitHub Actions builds the app and checks work storage, window geometry, and update detection. [Public repository](https://github.com/Cosmofang/cosmNotes-app)

To publish a release, update the version and build number in `Resources/Info.plist`. Push the matching `vMAJOR.MINOR.PATCH` tag for the merged commit. GitHub Actions publishes the universal ZIP and its SHA-256 checksum to Releases.

## License

[MIT](LICENSE)
