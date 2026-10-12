fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture App Store screenshots for every language (see Snapfile)

### ios upload_metadata

```sh
[bundle exec] fastlane ios upload_metadata
```

Upload the App Store listing in fastlane/metadata (all languages, review notes, URLs)

Doesn't touch screenshots, the build or the review submission

### ios upload_screenshots

```sh
[bundle exec] fastlane ios upload_screenshots
```

Upload fastlane/screenshots to App Store Connect, replacing the current ones

Needs an App Store Connect API key: see fastlane/README.md

### ios upload_iap

```sh
[bundle exec] fastlane ios upload_iap
```

Create or update the tips and Supporter subscription in App Store Connect

from Config/Tinytide.storekit and fastlane/in_app_purchases.yml.

Try `dry_run:true` first: it shows what would change without changing anything

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
