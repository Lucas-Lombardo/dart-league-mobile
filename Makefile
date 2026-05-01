.PHONY: help run-dev run-prod release-android release-ios release-ios-archive clean help

# Default target
help:
	@echo "Available commands:"
	@echo "  make run-dev          - flutter run with test Stripe key (env/dev.json)"
	@echo "  make run-prod         - flutter run with live Stripe key (env/prod.json)"
	@echo "  make release-android  - build signed App Bundle for Play Store"
	@echo "  make release-ios      - build iOS .ipa (release, no archive)"
	@echo "  make release-ios-archive - flutter build ios --release (Xcode archive next)"
	@echo "  make clean            - flutter clean + pub get"

# Run with dev (test) Stripe key
run-dev:
	flutter run --dart-define-from-file=env/dev.json

# Run with prod (live) Stripe key — useful for testing the live integration locally
run-prod:
	flutter run --dart-define-from-file=env/prod.json

# Android Play Store release
# Outputs build/app/outputs/bundle/release/app-release.aab
release-android:
	@if grep -q "REPLACE_ME" env/prod.json; then \
		echo "❌ env/prod.json still contains REPLACE_ME — set the live STRIPE_PUBLISHABLE_KEY first"; \
		exit 1; \
	fi
	flutter clean
	flutter pub get
	flutter build appbundle --release --dart-define-from-file=env/prod.json
	@echo "✅ AAB ready: build/app/outputs/bundle/release/app-release.aab"
	@echo "   Upload to Play Console → Internal testing or Production"

# iOS release - produces .ipa via flutter build ipa
# Requires signing config (codesign + provisioning profile) set up in Xcode
release-ios:
	@if grep -q "REPLACE_ME" env/prod.json; then \
		echo "❌ env/prod.json still contains REPLACE_ME — set the live STRIPE_PUBLISHABLE_KEY first"; \
		exit 1; \
	fi
	flutter clean
	flutter pub get
	flutter build ipa --release --dart-define-from-file=env/prod.json
	@echo "✅ IPA ready: build/ios/ipa/*.ipa"
	@echo "   Upload via Transporter or 'xcrun altool --upload-app …'"

# iOS release for archiving via Xcode (the GUI workflow)
# Run this, then open ios/Runner.xcworkspace and Product > Archive
release-ios-archive:
	@if grep -q "REPLACE_ME" env/prod.json; then \
		echo "❌ env/prod.json still contains REPLACE_ME — set the live STRIPE_PUBLISHABLE_KEY first"; \
		exit 1; \
	fi
	flutter clean
	flutter pub get
	flutter build ios --release --dart-define-from-file=env/prod.json
	@echo "✅ iOS release build complete"
	@echo "   Now open ios/Runner.xcworkspace in Xcode → Product → Archive"

# Clean build artefacts
clean:
	flutter clean
	flutter pub get
