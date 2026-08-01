# Overtype developer task entry point.
# Every target delegates to Swift Package Manager and the native swift toolchain.

.DEFAULT_GOAL := build
.PHONY: setup build build-app run test lint format clean upgrade-deps help

## setup: Resolve Swift package dependencies.
setup:
	swift package resolve

## build: Build the debug binary.
build:
	swift build

## build-app: Build the distributable Overtype.app bundle (release + ad-hoc sign).
build-app:
	./scripts/build-app.sh

## run: Build and launch the app bundle (a faithful menu-bar launch).
run: build-app
	open ./Overtype.app

## test: Run the unit test suite.
test:
	swift test

## lint: Check formatting and style with swift-format (reports only, no writes).
lint:
	swift format lint --recursive Sources Tests Package.swift

## format: Reformat sources in place with swift-format.
format:
	swift format --in-place --recursive Sources Tests Package.swift

## clean: Remove build artifacts and the generated app bundle.
clean:
	swift package clean
	rm -rf .build Overtype.app

## upgrade-deps: Update Swift package dependencies to the latest allowed versions.
## Note: KeyboardShortcuts is pinned with `exact:` in Package.swift, so moving it
## to a newer major/minor requires editing that pin by hand.
upgrade-deps:
	swift package update

## help: List available targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
