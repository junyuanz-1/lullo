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

3. `bundle exec fastlane upload_metadata`, `upload_screenshots` and `upload_iap`

## In-app purchases (`upload_iap`)

The three tips and the Supporter subscription are defined once, in
`Config/Tinytide.storekit`: product IDs, prices, the subscription group and
periods, and the display name and description in every language. Xcode uses
that file to test purchases; `upload_iap` creates or updates the same products
in App Store Connect, so the two never drift apart.

```sh
bundle exec fastlane iap_screenshots           # once, and when a purchase screen changes
bundle exec fastlane upload_iap dry_run:true   # read only: shows what would change
bundle exec fastlane upload_iap
```

For each product it sets the reference name, Family Sharing, the review note,
the text in every language, the price (other countries follow Apple's
equivalents) and availability in every territory, and uploads the review
screenshot. Whatever already matches is left alone, so run it as often as you
like. It never deletes anything.

To change something, edit `Tinytide.storekit` in Xcode (or as JSON), then run
the lane again. Limits, checked in CI by `fastlane/test/app_store_iap_test.rb`:
display name 30 characters, description 45. A new language needs its folder in
`fastlane/metadata/` first; StoreKit's `fr` or `de` map to `fr-FR` or `de-DE`.

What it leaves to App Store Connect:

- **Submitting.** The first in-app purchases are submitted together with an
  app version (tick them on the version page). Once a product is approved its
  text is locked: the lane then starts a new text version, which you submit
  for review in App Store Connect.
- **The price of a subscription that is on sale.** It affects existing
  subscribers, so the lane stops and asks you to change it there.
- **Turning Family Sharing off.** Apple doesn't allow it once it's on.

### Review screenshots

Extra details that the StoreKit file doesn't hold are in `in_app_purchases.yml`:
the note App Review reads for each product and its review screenshot. The
screenshots are generated, in English, into `fastlane/in_app_purchases/` by
`bundle exec fastlane iap_screenshots` (`tip_jar.png` and `supporter.png`).

`Tests/TinytideUITests/InAppPurchaseScreenshots.swift` opens each purchase
screen in demo mode and loads the products from the StoreKit file with a
StoreKit test session, so the prices show without an App Store account. If
StoreKit doesn't load them, the test fails instead of saving a screenshot
without prices. Then run **App Store screenshots** on GitHub Actions with
*in-app-purchases* and download the result, or take them by hand: run the app
from Xcode (its scheme uses the StoreKit file), open Settings > Support
Tinytide > Leave a Tip or Tinytide Supporter, and press ⌘S in the simulator.

Commit the screenshots, and capture them again when a purchase screen changes;
`upload_iap` replaces the ones in App Store Connect when the files change.
