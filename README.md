# Clockify Bar

A small native macOS menu bar frontend for Clockify. Start a timer from a rounded input, pick a project, or reuse a recent entry. A red menu bar icon shows when you’re tracking. Click it to open the widget and stop the timer.

Clockify handles your time entries; this app has no server, database, or third-party dependencies. This is an independent client, not an official Clockify application.

## Install — no build tools needed

Requires **macOS 13 Ventura or later**, a Clockify account, and an internet connection. The universal download runs on **Apple Silicon and Intel** Macs.

1. Open the [latest release](https://github.com/danilo-medeiros/clockify-bar/releases/latest).
2. Download **Clockify-Bar-VERSION-macOS-universal.zip** under **Assets**. Choose the app ZIP, not “Source code.”
3. Unzip it and drag **Clockify Bar.app** into **Applications**.
4. Open **Clockify Bar**. Look for the timer icon in the menu bar; the app does not appear in the Dock.
5. Paste your API key from [Clockify profile settings](https://app.clockify.me/user/settings) into the setup popup. Use the gear button to select another workspace if needed.

### First launch on macOS

These releases are **ad-hoc signed, not Apple Developer ID signed or notarized**. If macOS blocks the first launch, dismiss the message, open **System Settings → Privacy & Security**, and select **Open Anyway** for Clockify Bar. Confirm the prompt, then open the app again if needed. Only approve a download you trust. See [Apple’s guidance](https://support.apple.com/en-us/102445). An organization-managed Mac may require administrator help.

### Updates and launch at login

Quit Clockify Bar using the power button in its widget, download the newer release, and replace the app in Applications. Your Clockify timer continues running while the app is closed. The app retains your workspace preference and Keychain credential; macOS may request Keychain access again after an update. There is no automatic updater.

For launch at login, add **Clockify Bar** in **System Settings → General → Login Items**.

### Verify a download (optional)

Download `SHA256SUMS.txt` beside the app ZIP and run this in the folder containing both files:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

The ZIP should report `OK`.

The API key is saved in macOS Keychain; only the workspace ID is saved in preferences. Time entries are stored by Clockify. No credentials are bundled with the application or source code.

## Use

- **Idle:** the menu bar shows a timer outline, white on dark backgrounds and dark on light backgrounds for legibility. Click to open the popup.
- **Start:** type a description in the rounded input, click its folder icon to choose a project, and press Return or click the round Play button. The folder fills with the accent color when a project is selected; hover to see its name. The selected project’s billable setting is used. You can also click a recent entry to create a new timer with that entry’s description, project, task, tags, billability, and type; the dropdown does not override recent entries.
- **Running:** the same timer symbol appears in white on a red circular background. Click it to open the popup, then use **Stop tracking** to stop the timer.
- **Menu:** clicking the icon toggles the popup in any timer state. Right-click and Control-click also work. View elapsed time and recent entries, open Clockify, change settings, or quit. Recent-entry shortcuts become available once the timer is stopped.
- **Unknown status:** a question-mark icon indicates that status could not be verified. Open the popup and refresh; failed requests never silently show a stopped timer.
- **Open Clockify:** opens the web tracker, without starting an entry.

Recent entries show up to ten distinct activities from the latest fifty entries. Status syncs every five minutes, on wake, and on menu opening (with a 60-second cache); Refresh forces a check. Starts check for an existing timer first. Start/stop requests are never automatically retried, so a timeout cannot silently create duplicate entries. The next refresh reconciles with Clockify. Other clients can change state between checks, so the icon can lag behind changes made elsewhere. Stop targets the currently running timer in the selected workspace.

The project dropdown lists active projects from the selected workspace. Projects are cached for 15 minutes; Refresh reloads them immediately. Switching workspace clears the project selection. The selection stays available for subsequent new entries while the app is open.

Quitting or switching workspaces leaves timers running in Clockify. The app tracks one selected workspace at a time. Choosing “No project” creates a text-only entry; workspaces that require projects/tasks/tags/custom fields may reject entries missing those details. Use an appropriate recent entry or Clockify itself in that case. Required custom field values are not copied by this minimal client. The initial version uses Clockify’s global API endpoint; regional/custom-subdomain API routing is not implemented.

Clockify’s [Free plan API limit](https://clockify.me/help/getting-started/clockify-api-overview) is 30 requests per hour per workspace. Background status checks use at most 12/hour; opening the menu and creating/stopping entries consume additional requests. After a rate-limit response the app pauses requests for five minutes. A high-volume workflow may need a paid Clockify plan.

## Development

Building from source requires Xcode or compatible Swift tools (Swift 5.9+). Clone the repository, then build:

```sh
git clone https://github.com/danilo-medeiros/clockify-bar.git
cd clockify-bar
bash scripts/build-app.sh
open "dist/Clockify Bar.app"
```

To run during development or run the mocked test suite:

```sh
swift run ClockifyBar
swift test
```

`Sources/ClockifyCore` contains API requests and data models; `Sources/ClockifyBar` contains the AppKit status item, SwiftUI popup, tracking state, and Keychain storage. Tests use a mocked URL transport and never contact your Clockify account. API behavior follows the [Clockify API documentation](https://docs.clockify.me/).

Pushes to `main` and pull requests run tests on Apple Silicon and Intel Macs. Publishing a version tag builds and uploads the universal app to GitHub Releases. See [the release guide](docs/RELEASING.md) for the workflow and local packaging instructions.
