# Contributing to TennisWatch

Thanks for your interest. This is a small project but PRs and issues are welcome.

## Reporting bugs

Open an issue using the **Bug report** template. Helpful information to include:

- watchOS / iOS version, Apple Watch model
- Xcode version
- Exact phrase you said (Turkish or English) and what the watch did vs what you expected
- Network condition (Wi-Fi / cellular / paired-via-iPhone)
- Any console output from `print` calls in `AudioListenerManager` if visible

## Suggesting features

Open an issue using the **Feature request** template. Particularly welcome:

- Additional language support for voice commands
- Doubles match support
- Better tiebreak voice flow
- Replacement for scheme-env-var secrets (proper ephemeral-token backend for App Store builds)

## Submitting a PR

1. Fork → branch from `main` → make your change → open PR back to `main`.
2. Keep PRs small and focused. One concern per PR.
3. Match the existing code style (no SwiftLint config yet — just look at neighbouring code).
4. **Never commit API keys or secrets.** The repo's `.gitignore` excludes `xcuserdata/` (where scheme env vars live), but double-check `git diff --cached` before committing.
5. Test on a real Apple Watch if you touch the audio path — the simulator's microphone behaviour differs from device.
6. Update the README if your change affects setup or user-visible behaviour.

## Architecture quick reference

- `TennisWatch/AudioListenerManager.swift` — xAI WebSocket client, mic capture, format conversion. The seam where the model integration lives.
- `TennisWatch/ScoreManager.swift` — match state machine (points, games, sets, tiebreaks, undo). Pure logic, no networking.
- `TennisWatch/HeartRateManager.swift` — HealthKit + CoreLocation integration.
- `TennisApp/` — companion iOS app.

The voice prompt that tells xAI how to normalize speech lives in `AudioListenerManager.systemInstructions`. Most behavioural tweaks belong there.

## Code of conduct

By participating you agree to abide by the [Code of Conduct](CODE_OF_CONDUCT.md).
