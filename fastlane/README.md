# fastlane

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

3. `bundle exec fastlane upload_screenshots`
