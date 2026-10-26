# Codex Quota

[English](README.md) | [简体中文](README.zh-CN.md)

A native macOS quota app with a menu bar indicator and an optional **desktop widget**, showing your **remaining Codex subscription quota**.

```text
◉ 72% · wk 85%
```

Click the menu bar item to see usage bars, reset countdowns, exact reset times, and the last successful update. The app refreshes every 60 seconds and after wake, with a manual refresh button.

> This is an independent community app, not an official OpenAI product. It adds its own menu bar item; it does not modify the official Codex menu. The interface follows the macOS preferred language (Chinese or English; English fallback). Restart the app after changing the system or per-app language.

## Screenshot

![Codex Quota menu bar and quota panel in use](docs/images/codex-quota-screenshot.png)

Chinese interface shown. The app follows your macOS language preference and also supports English.

## Download and run

The current published v1.0.2 download is the menu bar edition. The native desktop widget is available in the source code; follow [Native macOS desktop widget](#native-macos-desktop-widget-source-build) to build and install it.

1. Install Codex and sign in using your **own ChatGPT account**. The app can find Codex bundled in `/Applications/Codex.app` or `/Applications/ChatGPT.app`, or a Codex CLI installation.
2. Download **Codex-Quota-macOS.zip** from [Releases](../../releases/latest).
3. Unzip it and drag **Codex Quota.app** into Applications.
4. Open the app. Its quota indicator appears in the macOS menu bar, with no Dock icon.

**Requirements:** macOS 14 or later, Apple Silicon or Intel, internet access, and an existing Codex ChatGPT login. The universal download includes both CPU architectures. End users do not need Swift, Python, or Node.js.

The release is ad-hoc signed, **not Apple-notarized**. macOS may block the first launch. If you trust the downloaded release, use System Settings → Privacy & Security → Open Anyway after attempting to open it, and follow the macOS prompt. You can also build the app yourself. There is no need to disable Gatekeeper globally.

To start at login, add the app under System Settings → General → Login Items. This is optional and is not changed automatically.

## Controls

- **Refresh** — refresh now.
- **Gear → Open Codex** — open the installed Codex/ChatGPT app.
- **Gear → Choose Codex executable…** — select your `codex` executable if auto-detection fails.
- **Gear → Hide menu bar icon (keep running)** — hide the indicator while background polling and widget sync continue; available in the current source build.
- **Gear → Quit** — quit the app and stop background quota updates.

The secondary menu bar label is `周` in Chinese or `wk` in English. The popup fits its content to avoid excess blank space, caps its height to the available screen area, and scrolls only when needed. Window labels use the server-reported duration; the common windows are five hours and one week. Missing information is shown as `—`. Failed reads keep the last successful snapshot with a warning; reaching the reset time does not locally assume that quota is back to 100%.

## Native macOS desktop widget (source build)

The Xcode project includes a native WidgetKit extension in **small** and **medium** sizes. After installing and launching the signed app:

1. Right-click the desktop and choose **Edit Widgets**.
2. Search for **Codex Quota**.
3. Choose a size and add it to the desktop or Notification Center. Remove it using the system widget menu whenever you want.

Widget controls:

- **↻** in the top-right corner requests fresh quota data. The button uses an icon only.
- **Updating… / Up to date / Update failed · Tap to retry** shows the request status.
- **Last update** always shows the last successful data-fetch time, including during a new request or after a failure. Before the first successful request, it shows **Never**.

This extension is not included in the existing v1.0.2 download or the simple `scripts/build.sh` build. To build it:

1. Open `CodexQuota.xcodeproj` in Xcode.
2. Select your development team for **both** targets. If needed, choose unique host and extension bundle identifiers.
3. Configure the same App Group on both targets. The default entitlements and `QuotaAppGroup` Info.plist key use `$(TeamIdentifierPrefix)local.codex.quota`; if your team's group identifier differs, update all four configuration files consistently.
4. Build the **CodexQuota** scheme, install the signed app in Applications, and launch it to sync the first quota snapshot. Then add the widget using macOS Edit Widgets.

Refreshing provides system loading feedback and a brief arrow animation. Failed requests retain the last successful quota. An interrupted refresh stops showing as pending after 35 seconds. WidgetKit limits animation duration, so the arrow does not spin indefinitely.

The menu bar app writes only quota percentages, window durations, reset times, update time, refresh timestamps, and failure status into its shared App Group container. The widget never reads login tokens or launches Codex itself. Keep the app running in the background for fresh data. It queries Codex every 60 seconds and asks WidgetKit to reload; the widget also requests a timeline update after 15 minutes. **macOS controls the actual render schedule**, so these requests do not guarantee a visible update every minute. Clicking ↻ runs a refresh action in the host app and waits for completion; clicking elsewhere in the widget also opens the app to request a refresh. Data older than three minutes is marked out of date.

Unsigned builds can verify compilation but do not verify installation, App Group access, or appearance in the widget gallery. A valid signing setup is required for end-to-end testing and distribution.

To keep only the desktop widget, choose **Gear → Hide menu bar icon (keep running)**. Quota polling and widget sync continue in the background, and the hidden state is remembered across launches. Open Codex Quota again while it is running to restore its menu bar icon. **Quit** stops background updates; hiding the icon does not.

## Which account does it use?

The app launches the local `codex app-server` and reads its existing authentication state. It does not embed the author's account, ask you to paste tokens, or read authentication files directly. When shared, it reads **the recipient's local Codex account**.

If you use multiple Codex installations or different `CODEX_HOME` environments, the selected process may use a different account from an open desktop window. The current UI does not show the account email. Check the selected Codex environment if the numbers look unfamiliar. Switching accounts is handled in Codex; refresh this app afterward.

Executable lookup order:

1. `CODEX_BIN` environment variable (useful for testing or launching from a shell).
2. Path selected in the app.
3. Codex/ChatGPT app bundles in `/Applications`.
4. `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, and `PATH`.

Finder-launched apps may not inherit your shell environment. Use the file picker for custom CLI locations.

## Build from source

Install Apple Command Line Tools (`xcode-select --install`) or Xcode. Use a recent Swift toolchain, then run these commands from the cloned repository:

```sh
./scripts/build.sh
open "dist/Codex Quota.app"
```

The default build targets your Mac's architecture. Build the universal release zip with:

```sh
./scripts/package.sh
```

Outputs are `dist/Codex-Quota-macOS.zip` and `dist/SHA256SUMS.txt`. Build and package scripts only write inside this repository. They do not install the app or register a login item.

## Test and diagnose

```sh
./scripts/build.sh
./scripts/test.sh
"dist/Codex Quota.app/Contents/MacOS/CodexQuota" --probe
```

The tests require Python 3 for a local mock server. They do not need a Codex login or network access. Tests cover named quota buckets, missing fields, percentage bounds, duration labels, initialization, unrelated notifications, error propagation, widget snapshot compatibility, and refresh success/failure/timeout states. `--probe` is a separate live check using your own login and prints only remaining percentages.

If a read fails:

- Confirm that the selected Codex is signed in with a ChatGPT account, rather than only an API key.
- Check the network connection, then use **Refresh**.
- Select the correct executable through the gear menu if Codex is installed somewhere else.
- Reads time out after 30 seconds; the app will try again at the next refresh.

## Optional Codex companion plugin

[`plugins/codex-quota`](plugins/codex-quota) contains a companion skill that tells Codex how to build, launch, and diagnose this repository. **It is not required to run the app.** It is not published to the official plugin directory or automatically installed by these scripts.

The plugin alone does not contain the native application. Keep the repository available and tell Codex its location. Enabling or disabling the plugin does not start or stop the app; to stop the app, use its Quit menu.

## Implementation and privacy

Uses the documented [Codex App Server](https://learn.chatgpt.com/docs/app-server) stdio protocol: `initialize`, `initialized`, then `account/rateLimits/read`. Each read closes its subprocess afterward. Refreshes do not start a conversation or make model inference requests.

- Prefers `rateLimitsByLimitId.codex`, with a legacy `rateLimits` fallback.
- Calculates remaining percentage as `100 - usedPercent`, clamped to 0–100.
- Does not collect analytics or send quota data to a project-owned server.
- The basic menu bar build does not store quota snapshots. The signed WidgetKit build stores a minimal snapshot in its App Group container; neither build stores login credentials. Codex maintains its own authentication and runtime state.
- Shows subscription quota only, not OpenAI API billing balances or separate ChatGPT web message limits.
- Polls once per minute; it is not a second-by-second push feed.

The binary is compiled for macOS 14+, but runtime validation has currently been performed on an Apple Silicon Mac running macOS 26. Intel and older supported macOS versions need additional user testing.

## License

[MIT](LICENSE).
