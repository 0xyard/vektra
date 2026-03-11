PROJECT := Vektra.xcodeproj
TARGET  := Vektra
CONFIG  ?= Debug

.PHONY: build clean archive

build:
	xcodebuild -project "$(PROJECT)" -target "$(TARGET)" -configuration "$(CONFIG)" -destination 'platform=macOS' build

clean:
	xcodebuild -project "$(PROJECT)" -target "$(TARGET)" -configuration "$(CONFIG)" clean

archive:
	xcodebuild -project "$(PROJECT)" -scheme "$(TARGET)" -configuration Release -destination 'platform=macOS' archive

