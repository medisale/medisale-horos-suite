HOROS_APP ?= /Applications/Horos.app
HOROS_HEADERS := $(HOROS_APP)/Contents/Frameworks/Horos.framework/Versions/A/Headers
BUILD_DIR := build
BUNDLE := $(BUILD_DIR)/MedisalePlugin.osirixplugin
EXECUTABLE := $(BUNDLE)/Contents/MacOS/MedisalePlugin
SOURCES := plugin/MedisalePluginFilter.m plugin/ImageContext.m plugin/HorosAdapter.m plugin/MeasurementContextConsumer.m plugin/TwoPointInputController.m plugin/LineOverlayModel.m plugin/TransientLineOverlayController.m plugin/GuidePreferenceStore.m plugin/GuideEngine.m plugin/MeasurementRecord.m plugin/SQLiteMeasurementStore.m plugin/ViewerInspectorPanelHost.m plugin/CompactGuideViewState.m plugin/CompactGuidePresentation.m plugin/CompactGuideLayoutPolicy.m plugin/CompactGuideLocalization.m
RESOURCE_FILES := $(shell find plugin/Resources -type f -print)
PERSISTENCE_TEST := $(BUILD_DIR)/PersistenceStoreTests
COMPACT_GUIDE_TEST := $(BUILD_DIR)/CompactGuideTests

.PHONY: all clean sign verify test-persistence test-compact-guide

all: $(EXECUTABLE)

$(EXECUTABLE): $(SOURCES) plugin/Info.plist $(RESOURCE_FILES)
	@test -f "$(HOROS_HEADERS)/PluginFilter.h" || { echo "STOP: real PluginFilter.h not found"; exit 20; }
	mkdir -p "$(BUNDLE)/Contents/MacOS"
	cp plugin/Info.plist "$(BUNDLE)/Contents/Info.plist"
	mkdir -p "$(BUNDLE)/Contents/Resources"
	cp -R plugin/Resources/. "$(BUNDLE)/Contents/Resources/"
	clang -arch arm64 -fobjc-arc -fmodules -bundle -undefined dynamic_lookup \
		-isysroot "$$(xcrun --sdk macosx --show-sdk-path)" \
		-fmodules-cache-path="$(BUILD_DIR)/ModuleCache" \
		-mmacosx-version-min=10.15 \
		-I"$(HOROS_HEADERS)" \
		-framework Cocoa \
		-lsqlite3 \
		-o "$@" $(SOURCES)

sign: all
	codesign --force --sign - --timestamp=none "$(BUNDLE)"

verify: sign
	@file "$(EXECUTABLE)" | grep -q 'Mach-O 64-bit bundle arm64'
	@otool -hv "$(EXECUTABLE)" | grep -q ARM64
	@nm -u "$(EXECUTABLE)" | grep -q '_OBJC_CLASS_$$_PluginFilter'
	@nm "$(EXECUTABLE)" | grep -q 'toolbarAllowedIdentifiersForViewer:'
	@nm "$(EXECUTABLE)" | grep -q 'toolbarItemForItemIdentifier:forViewer:'
	@nm "$(EXECUTABLE)" | grep -q 'toolbarAllowedIdentifiersForBrowserController:'
	@nm "$(EXECUTABLE)" | grep -q 'toolbarItemForItemIdentifier:forBrowserController:'
	@nm "$(EXECUTABLE)" | grep -q 'databaseSelection'
	@nm "$(EXECUTABLE)" | grep -q 'currentImage'
	@nm "$(EXECUTABLE)" | grep -q 'imageContextForViewer:error:'
	@nm "$(EXECUTABLE)" | grep -q 'mouseXPos'
	@nm "$(EXECUTABLE)" | grep -q 'ConvertFromGL2NSView'
	@nm "$(EXECUTABLE)" | grep -q 'ConvertFromNSView2GL'
	@nm "$(EXECUTABLE)" | grep -q 'OsirixDCMViewIndexChangedNotification'
	@! rg -q 'ViewerController|DCMPix|DicomImage|NSManagedObject|ROI' plugin/ImageContext.h plugin/ImageContext.m plugin/MeasurementContextConsumer.h plugin/MeasurementContextConsumer.m
	@! rg -q 'NSManagedObject|NSUserDefaults|standardUserDefaults|addROI|setROI|saveDocument|writeToFile|sqlite3_|DicomDatabase' plugin/LineOverlayModel.h plugin/LineOverlayModel.m plugin/TransientLineOverlayController.h plugin/TransientLineOverlayController.m
	@rg -q 'pixelDistance' plugin/LineOverlayModel.h plugin/LineOverlayModel.m plugin/TransientLineOverlayController.m
	@rg -q '@protocol MeasurementPanelHost' plugin/MeasurementPanelHost.h
	@rg -q '@protocol GuidePreferenceStore' plugin/GuidePreferenceStore.h
	@rg -q 'GuideEngineDidChangeNotification' plugin/GuideEngine.h plugin/GuideEngine.m plugin/ViewerInspectorPanelHost.m
	@rg -q 'guide.short.instructions' plugin/GuideEngine.m plugin/Resources/en.lproj/Localizable.strings plugin/Resources/ja.lproj/Localizable.strings
	@rg -q 'CFPreferencesCopyValue' plugin/GuidePreferenceStore.m
	@rg -q 'CFPreferencesSetValue' plugin/GuidePreferenceStore.m
	@rg -q 'kCFPreferencesCurrentUser' plugin/GuidePreferenceStore.m
	@rg -q 'kCFPreferencesAnyHost' plugin/GuidePreferenceStore.m
	@! rg -q 'kCFPreferencesAnyUser|kCFPreferencesCurrentHost|kCFPreferencesAnyApplication|NSUserDefaults|standardUserDefaults' plugin/GuidePreferenceStore.h plugin/GuidePreferenceStore.m plugin/GuideEngine.h plugin/GuideEngine.m
	@rg -q 'ViewerInspectorPanelHost' plugin/MedisalePluginFilter.m plugin/ViewerInspectorPanelHost.h plugin/ViewerInspectorPanelHost.m
	@rg -q '@protocol MeasurementPersistenceStore' plugin/MeasurementPersistenceStore.h
	@rg -q 'BEGIN IMMEDIATE' plugin/SQLiteMeasurementStore.m
	@rg -q 'ROLLBACK' plugin/SQLiteMeasurementStore.m
	@rg -q 'sqlite3_prepare_v2' plugin/SQLiteMeasurementStore.m
	@rg -q 'PRAGMA foreign_keys = ON' plugin/SQLiteMeasurementStore.m
	@rg -q 'SQLITE_OPEN_READONLY' plugin/SQLiteMeasurementStore.m
	@rg -q 'PRAGMA query_only = ON' plugin/SQLiteMeasurementStore.m
	@rg -q 'latestMeasurementForImageContext' plugin/MeasurementPersistenceStore.h plugin/SQLiteMeasurementStore.m plugin/MedisalePluginFilter.m
	@rg -q 'OsirixViewerControllerDidLoadImagesNotification' plugin/MedisalePluginFilter.m
	@rg -q 'OsirixDCMViewIndexChangedNotification' plugin/MedisalePluginFilter.m
	@rg -q 'willUnload' plugin/MedisalePluginFilter.m
	@! rg -q 'ViewerController|DCMPix|DicomImage|NSManagedObject|ROI' plugin/MeasurementRecord.h plugin/MeasurementRecord.m plugin/MeasurementPersistenceStore.h plugin/SQLiteMeasurementStore.h plugin/SQLiteMeasurementStore.m
	@! rg -q 'sqlite3_|BEGIN IMMEDIATE|COMMIT|ROLLBACK|CREATE TABLE|INSERT INTO|UPDATE ' plugin/MedisalePluginFilter.m plugin/ViewerInspectorPanelHost.m plugin/LineOverlayModel.m plugin/TransientLineOverlayController.m
	@! rg -qi 'patient.?name|patient.?id|birth.?date|thumbnail|pixel.?data|study.?name|series.?name|dicom.?path' plugin/MeasurementRecord.h plugin/MeasurementRecord.m plugin/MeasurementPersistenceStore.h plugin/SQLiteMeasurementStore.h plugin/SQLiteMeasurementStore.m
	@! rg -q 'method_exchangeImplementations|object_getIvar|class_getInstanceVariable|valueForKey.*split|viewer\.(splitView|contentView)|->(splitView|contentView)' plugin/MeasurementPanelHost.h plugin/ViewerInspectorPanelHost.h plugin/ViewerInspectorPanelHost.m
	@! rg -q 'NSManagedObject|NSUserDefaults|standardUserDefaults|CFPreferences|GuidePreferenceStore|addROI|setROI|saveDocument|writeToFile|sqlite3_|DicomDatabase|NSURLSession|NSURLConnection' plugin/MeasurementPanelHost.h plugin/ViewerInspectorPanelHost.h plugin/ViewerInspectorPanelHost.m
	@! rg -qi 'VHS|VLAS|CTR|diagnos|normal value|abnormal' plugin/GuideEngine.h plugin/GuideEngine.m plugin/GuidePreferenceStore.h plugin/GuidePreferenceStore.m
	@rg -q 'CompactGuideMeasurementStateCalculatedUnconfirmed' plugin/CompactGuideViewState.h plugin/CompactGuideViewState.m plugin/ViewerInspectorPanelHost.m
	@rg -q 'CompactGuideMeasurementStateModifiedAfterConfirmation' plugin/CompactGuideViewState.h plugin/CompactGuideViewState.m plugin/ViewerInspectorPanelHost.m
	@rg -q 'CompactGuideSemanticRoleAttention' plugin/CompactGuidePresentation.h plugin/CompactGuidePresentation.m plugin/ViewerInspectorPanelHost.m
	@rg -q 'CompactGuideLayoutModeNarrow' plugin/CompactGuideLayoutPolicy.h plugin/CompactGuideLayoutPolicy.m
	@rg -q 'guide.access.confirmation.help' plugin/Resources/en.lproj/Localizable.strings plugin/Resources/ja.lproj/Localizable.strings
	@rg -q 'self.detailsButton.nextKeyView = self.cancelButton' plugin/ViewerInspectorPanelHost.m
	@rg -q 'self.cancelButton.nextKeyView = self.confirmButton' plugin/ViewerInspectorPanelHost.m
	@rg -q 'self.confirmButton.nextKeyView = self.detailsButton' plugin/ViewerInspectorPanelHost.m
	@! rg -q 'ViewerController|DCMPix|DicomImage|NSManagedObject|ROI|NSUserDefaults|standardUserDefaults|CFPreferences|sqlite3_|NSURLSession|NSURLConnection|writeToFile' plugin/CompactGuideViewState.h plugin/CompactGuideViewState.m plugin/CompactGuidePresentation.h plugin/CompactGuidePresentation.m plugin/CompactGuideLayoutPolicy.h plugin/CompactGuideLayoutPolicy.m plugin/CompactGuideLocalization.h plugin/CompactGuideLocalization.m
	@! rg -qi 'clinical suitability decision[^\n]*YES|automatically suitable|patient.?name|patient.?id|manufacturer|implant|plate|saw blade' plugin/CompactGuideViewState.h plugin/CompactGuideViewState.m plugin/CompactGuideLayoutPolicy.h plugin/CompactGuideLayoutPolicy.m plugin/CompactGuideLocalization.h plugin/CompactGuideLocalization.m plugin/Resources
	@plutil -lint "$(BUNDLE)/Contents/Info.plist"
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :NSPrincipalClass' "$(BUNDLE)/Contents/Info.plist")" = MedisalePluginFilter
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :MenuTitles:0' "$(BUNDLE)/Contents/Info.plist")" = 'Medisale Plugin'
	@test "$$(/usr/libexec/PlistBuddy -c 'Print :pluginType' "$(BUNDLE)/Contents/Info.plist")" = imageFilter
	@codesign --verify --strict --verbose=2 "$(BUNDLE)"
	@$(MAKE) --no-print-directory test-persistence
	@$(MAKE) --no-print-directory test-compact-guide
	@echo "PASS: ad-hoc-signed arm64 bundle uses the real PluginFilter runtime class"

$(PERSISTENCE_TEST): tests/PersistenceStoreTests.m plugin/ImageContext.m plugin/MeasurementRecord.m plugin/SQLiteMeasurementStore.m
	mkdir -p "$(BUILD_DIR)"
	clang -arch arm64 -fobjc-arc -fmodules \
		-isysroot "$$(xcrun --sdk macosx --show-sdk-path)" \
		-fmodules-cache-path="$(BUILD_DIR)/ModuleCache" \
		-mmacosx-version-min=10.15 \
		-Iplugin -framework Foundation -lsqlite3 \
		-o "$@" $^

test-persistence: $(PERSISTENCE_TEST)
	@"$(PERSISTENCE_TEST)"

$(COMPACT_GUIDE_TEST): tests/CompactGuideTests.m plugin/ImageContext.m plugin/CompactGuideViewState.m plugin/CompactGuidePresentation.m plugin/CompactGuideLayoutPolicy.m plugin/CompactGuideLocalization.m
	mkdir -p "$(BUILD_DIR)"
	clang -arch arm64 -fobjc-arc -fmodules \
		-isysroot "$$(xcrun --sdk macosx --show-sdk-path)" \
		-fmodules-cache-path="$(BUILD_DIR)/ModuleCache" \
		-mmacosx-version-min=10.15 \
		-Iplugin -framework Cocoa \
		-o "$@" $^

test-compact-guide: $(COMPACT_GUIDE_TEST)
	@"$(COMPACT_GUIDE_TEST)"

clean:
	rm -rf "$(BUILD_DIR)"
