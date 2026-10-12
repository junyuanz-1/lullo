# fastlane

Release tooling only. Nothing in `fastlane/` is part of the Xcode project, so
none of it is bundled into the app (`scripts/check_store_metadata.py` checks
this in CI). The release checklist is in [`docs/release/README.md`](../docs/release/README.md).

## App Store listing (`metadata/`)

The text shown on the App Store, in all 9 languages, in
[fastlane deliver's format](https://docs.fastlane.tools/actions/deliver/):

| File | Field | Limit |
|---|---|---|
| `metadata/<language>/name.txt` | App name | 30 |
| `metadata/<language>/subtitle.txt` | Subtitle | 30 |
| `metadata/<language>/promotional_text.txt` | Promotional text (can change without a new version) | 170 |
| `metadata/<language>/description.txt` | Description | 4000 |
| `metadata/<language>/keywords.txt` | Keywords, comma separated, no spaces | 100 |
| `metadata/<language>/release_notes.txt` | What's New (add from version 1.1 on) | 4000 |
| `metadata/<language>/*_url.txt` | Privacy policy, support and marketing URLs | |
| `metadata/review_information/notes.txt` | Notes for App Review | 4000 |
| `metadata/copyright.txt`, `*_category.txt` | Shared by all languages | |

Edit the files, then check and upload:

```sh
python3 scripts/check_store_metadata.py   # also runs in CI
bundle exec fastlane upload_metadata      # needs the API key below
```

Keep the languages in step with `languages(...)` in `Snapfile`. The App
Review contact name and phone number are entered in App Store Connect, not
stored here.

## App Store screenshots

```sh
bundle install                      # once
bundle exec fastlane screenshots    # ~20 min: 9 languages x 6 screens
```

Screenshots land in `fastlane/screenshots/<language>/` (git-ignored). The
screens and their order are in `Tests/TinytideUITests/AppStoreScreenshots.swift`;
the sample data is `DemoData` in BabyCore. To see demo mode yourself, add the
launch argument `-demoMode` (and optionally `-demoScreen trends`) to the
Tinytide scheme in Xcode.

You can also run the **App Store screenshots** workflow on GitHub Actions and
download the result as an artifact.

## Uploading to App Store Connect

1. App Store Connect → Users and Access → Integrations → App Store Connect API →
   create a key with the *App Manager* role and download the `.p8` file.
2. Save `fastlane/asc_api_key.json` (git-ignored):

   ```json
   {
     "key_id": "ABC123XYZ",
     "issuer_id": "00000000-0000-0000-0000-000000000000",
     "key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----",
     "in_house": false
   }
   ```

3. `bundle exec fastlane upload_metadata` and `bundle exec fastlane upload_screenshots`
