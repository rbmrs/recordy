# Releasing Recordy

Recordy's public install path is Homebrew Cask, served from this repository —
the app repo doubles as its own Homebrew tap:

```sh
brew tap rbmrs/recordy https://github.com/rbmrs/recordy
brew trust rbmrs/recordy
brew install --cask recordy
```

The cask lives at `Casks/recordy.rb`. The two-argument `brew tap` form is needed
because the repo is named `recordy`, not `homebrew-recordy`, and `brew trust`
is required on Homebrew 6.0+, which refuses to load third-party taps until they
are explicitly trusted.

`scripts/package-release.sh` regenerates `Casks/recordy.rb` from the same build
it zips, so the cask's `sha256` always matches the uploaded artifact. The release
workflow commits that regenerated cask back to `main`.

## Requirements

- A Swift toolchain. The universal binary is built by compiling each
  architecture separately and merging them with `lipo`, so plain Command Line
  Tools are sufficient — full Xcode is not required.
- Homebrew, for validating the generated cask.
- GitHub permission to publish releases in `rbmrs/recordy`. The cask bump is a
  same-repo push using the workflow's default `GITHUB_TOKEN` — no PAT needed.
  (It does require `main` to allow direct pushes from `github-actions[bot]`.)

No Apple Developer Program membership is required. Releases are ad-hoc signed
with Recordy's stable bundle identifier, so they are not notarized; the cask
strips the quarantine flag on install so the app still launches.

## Release Flow

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Resources/Info.plist`.
2. Verify the app builds:

   ```sh
   swift build -c release
   ```

3. Package the universal app:

   ```sh
   ./scripts/package-release.sh
   ```

   This creates:

   ```text
   dist/release/Recordy-<version>.zip
   dist/release/SHA256SUMS.txt
   dist/release/recordy.rb
   ```

4. Verify the built bundle:

   ```sh
   plutil -lint dist/build/Recordy.app/Contents/Info.plist
   codesign --verify --deep --strict --verbose=2 dist/build/Recordy.app
   lipo -info dist/build/Recordy.app/Contents/MacOS/recordy   # arm64 + x86_64
   shasum -a 256 dist/release/Recordy-<version>.zip
   ```

5. Create and push a version tag:

   ```sh
   git tag v<version>
   git push origin v<version>
   ```

   The release workflow then builds the universal app, publishes the GitHub
   release, and commits the regenerated `Casks/recordy.rb` to `main`.

6. Manual fallback (only if the workflow is disabled): upload
   `dist/release/Recordy-<version>.zip` and `dist/release/SHA256SUMS.txt` to the
   release, then copy `dist/release/recordy.rb` over `Casks/recordy.rb`, commit,
   and push to `main`.

7. Test the published cask:

   ```sh
   brew tap rbmrs/recordy https://github.com/rbmrs/recordy
   brew trust rbmrs/recordy
   brew style --cask Casks/recordy.rb
   brew install --cask recordy
   open -a Recordy
   ```

## Manual Acceptance

- First launch works from the Brew-installed app.
- First capture asks for Screen Recording permission.
- Upgrading between cask versions preserves Screen Recording permission where
  macOS allows it.
