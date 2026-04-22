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

### ios create_appstore_app

```sh
[bundle exec] fastlane ios create_appstore_app
```

Create app on App Store Connect if missing

### ios upload_ipa_to_testflight

```sh
[bundle exec] fastlane ios upload_ipa_to_testflight
```

Upload an existing IPA to TestFlight

### ios create_build_upload

```sh
[bundle exec] fastlane ios create_build_upload
```

Create app (if needed), build IPA, and upload to TestFlight

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
