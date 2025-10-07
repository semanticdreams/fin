# Repository Guidelines

## Project Structure & Module Organization
Primary Flutter app code lives in `lib/`, with `lib/main.dart` as the entry point and shared widgets composed nearby. Tests sit in `test/`, starting with `test/widget_test.dart`. Platform wrappers and native assets are under `android/`, `ios/`, `macos/`, `linux/`, `web/`, and `windows/`; adjust platform-specific code there only when required. Add new static assets under an `assets/` folder and register them inside `pubspec.yaml`. Generated build outputs in `build/` remain untracked—never commit them.

## Environment Setup
Use Flutter SDK 3.9 or newer to match the `sdk` constraint in `pubspec.yaml`. Run `flutter pub get` whenever dependencies change to refresh `.dart_tool/` metadata. The analyzer obeys `analysis_options.yaml`; consult it before tweaking lint behavior and prefer local suppressions over global disables.

## Build, Test, and Development Commands
- `flutter analyze` — run static analysis with the repository lint configuration.
- `flutter test` — execute the unit and widget suite in `test/`.
- `flutter run -d chrome` — launch the web target for rapid UI reviews.
- `flutter build apk --release` — produce a signed Android build; bump version fields first.

## Coding Style & Naming Conventions
Stick to Flutter defaults: two-space indentation, `UpperCamelCase` for classes, `lowerCamelCase` for members, and `SCREAMING_CAPS` for constants. Keep widgets small and composable; extract layout helpers as private methods or widgets within the same file. Prefer `const` constructors where eligible and follow lint guidance from `flutter_lints`.

## Testing Guidelines
Mirror the production structure under `test/`, naming files `*_test.dart`. Describe behaviors in test names (`BudgetSummaryCard_displaysTotals`). Run `flutter test --coverage` before opening a PR and maintain or improve coverage when adding features. Add golden tests for visual components when layout regressions are likely.

## Commit & Pull Request Guidelines
Current history uses terse imperative commits (e.g., `Add all`); continue with `<verb> <scope>` subjects under 60 characters and document rationale in the body. Reference related issues (`Closes #123`) and note any platform-specific considerations. PRs should include a summary of changes, testing notes (commands run), and screenshots for UI-affecting work. Await green checks from CI or local equivalents before requesting review.
