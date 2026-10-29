# Convenience targets. Everything runs locally; no network access is required.

.PHONY: build app dmg run test test-offline xcodeproj uitest clean

build:            ## Debug build of the core and app
	swift build

app:              ## Release Local Explorer.app (arm64) in ./build
	scripts/build-app.sh

dmg:              ## Drag-to-install build/LocalExplorer-<version>.dmg
	scripts/build-dmg.sh

run: app          ## Build and launch the app
	open "build/Local Explorer.app"

test:             ## Unit + integration tests (ExplorerCore)
	swift test

test-offline:     ## Same tests with networking blocked for the test process (macOS)
	scripts/offline-test.sh

xcodeproj:        ## Generate LocalExplorer.xcodeproj with UI tests (needs XcodeGen)
	xcodegen generate

uitest: xcodeproj ## UI tests (needs Xcode; grant Accessibility to Xcode/xcodebuild when asked)
	xcodebuild test -project LocalExplorer.xcodeproj -scheme LocalExplorer \
	  -destination 'platform=macOS,arch=arm64' -only-testing:LocalExplorerUITests

clean:
	rm -rf .build build LocalExplorer.xcodeproj
