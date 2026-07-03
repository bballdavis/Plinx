# Privacy And Safety

## Core Policy

Plinx is built around three non-negotiable rules:

- kid safety comes first
- zero collection is the privacy baseline
- kid-facing UI must not expose external links

## Zero-Collection Implementation

Current implementation anchors:

- `PlinxApp/Resources/PrivacyInfo.xcprivacy` declares no tracking, no collected data types, and no accessed API types
- `PlinxApp/App/ErrorReporter.swift` is a no-op reporter so no crash or analytics SDK is active
- `PlinxApp/project.yml` excludes Strimr's reporting implementation and wires in the no-op replacement

Do not add analytics, crash reporting, telemetry, or usage tracking without explicitly changing product policy and documentation first.

## Kid-Safety Boundaries

Safety-critical behavior lives primarily in:

- `Packages/PlinxCore/Sources/PlinxCore/Safety/`
- parental gate flows in `PlinxApp/Views/ParentalGateView.swift` and related settings flows
- Plinx adapters/decorators that filter or reshape upstream content before display

Safety behavior should fail closed whenever possible. If filtering metadata is missing or uncertain, the default should not broaden kid-facing visibility by accident.

## External Link Policy

- No external links in kid-facing UI.
- Any legal, attribution, or source links belong behind parental gate or settings surfaces.
- Repository docs and release material may link externally; the restriction applies to the app experience.

## Secrets Handling

`test_creds.yaml.example` is the template for local live-test credentials.

Rules:

- keep the real `test_creds.yaml` local only
- never commit Plex tokens, credentials, or account secrets
- avoid logging raw tokens in scripts, tests, or app code
- when adding new live-test credentials, document them in `test_creds.yaml.example`

## Logging Guidance

- do not log auth tokens, passwords, or raw secrets
- prefer aggregate counts, identifiers already visible in the UI, or redacted forms when debugging is necessary
- if a new log touches safety or identity-sensitive data, review it as a privacy change

## Release Validation Expectations

Before release or archive-oriented changes are considered safe, verify:

- `PrivacyInfo.xcprivacy` is included in the app bundle
- launch resources and asset catalogs are present
- zero-collection behavior is still intact
- relevant safety and branding tests still pass

Use:

```bash
./scripts/tests/validate_testflight_archive.sh
```

## Minimum Tests For Sensitive Changes

| Change area | Minimum tests |
|---|---|
| Safety filtering, rating logic, parental gate | `PlinxCore` tests plus relevant app unit tests |
| Branding or kid-facing safety surfaces | Branding tests plus snapshot/UI coverage |
| Logging, privacy manifest, reporter, or secret flow | App/unit tests touched by the change plus archive validation when packaging is affected |
| Real-data filtering behavior | live smoke and/or live parity checks when applicable |
