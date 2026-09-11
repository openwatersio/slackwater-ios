# Slackwater for iOS

Tide and current predictions that keep working when the signal does not.
Slackwater computes predictions on your iPhone, so the answer is already there
before you leave the dock.

- Tide predictions worldwide
- Current predictions across the United States and Canada
- Slack times, speed and direction for tidal currents
- Offline charts and station search
- No account, no ads and no tracking

Slackwater is free and currently available as a public beta for iOS 26 and
later.

**[Get Slackwater on TestFlight](https://testflight.apple.com/join/FCSS4w8s)**

See screenshots, explore stations and learn how the predictions work at
**[slackwater.xyz](https://slackwater.xyz)**.

> Predictions are not observations. Weather, river flow and local conditions
> can change the water. Slackwater is not for navigation.

## Coverage and offline use

Slackwater includes thousands of tide and current stations from sources
including NOAA and the Canadian Hydrographic Service. Most predictions are
calculated from harmonic constituents on the device. When a source can only be
used online, or a prediction has lower confidence, the app says so.

The app downloads chart coverage and Canadian station data as you use it.
Previously downloaded predictions and chart areas remain available without a
connection.

## Help improve Slackwater

Found a bug or a prediction that looks wrong? [Open an
issue](https://github.com/openwatersio/slackwater-ios/issues/new?template=bug_report.yml).

You can also email [slackwater@openwaters.io](mailto:slackwater@openwaters.io)
or visit [Slackwater support](https://slackwater.xyz/support/).

## Related projects

- [Slackwater Engine](https://github.com/openwatersio/slackwater-engine) — the
  Swift harmonic prediction engine used by the app
- [Open Waters](https://openwaters.io) — the organization behind Slackwater

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup,
tests and pull-request guidance. You will need Xcode 26 or later and XcodeGen;
then run `xcodegen generate` and open `Slackwater.xcodeproj`.

## License

Slackwater is © Open Water Software, LLC and licensed under
[GPL-3.0](LICENSE.md). Contributions require signing the
[CLA](CLA.md) — [docs/licensing.md](docs/licensing.md) explains why a GPL app
on the App Store needs one. Bundled data and third-party code are credited in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
