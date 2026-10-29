export THEOS_PACKAGE_SCHEME = rootless
THEOS ?= /opt/theos
TARGET := iphone:clang:27.0:15.0
ARCHS := arm64 arm64e
include $(THEOS)/makefiles/common.mk

TWEAK_NAME := NoAccl
NoAccl_FILES := Tweak.xm NoAcclPolicy.m NoAcclRule.m NoAcclStore.m NoAcclLocalization.m
NoAccl_CFLAGS := -fobjc-arc -Wno-deprecated-declarations
NoAccl_FRAMEWORKS := Foundation UIKit CoreMotion
NoAccl_EXTRA_FRAMEWORKS := Cephei

BUNDLE_NAME := NoAcclPrefs
NoAcclPrefs_FILES := NoAcclPrefs/NoAcclPrefs.m NoAcclPolicy.m NoAcclRule.m NoAcclStore.m NoAcclLocalization.m
NoAcclPrefs_FRAMEWORKS := Foundation UIKit
NoAcclPrefs_PRIVATE_FRAMEWORKS := Preferences
NoAcclPrefs_LDFLAGS := -F$(THEOS_PROJECT_DIR)/vendor
NoAcclPrefs_INSTALL_PATH := /Library/PreferenceBundles
NoAcclPrefs_RESOURCE_DIRS := NoAcclPrefs/Resources
NoAcclPrefs_EXTRA_FRAMEWORKS := CepheiPrefs Cephei
NoAcclPrefs_CFLAGS := -fobjc-arc -Wno-deprecated-declarations

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

test: tools/test_rule_model.m NoAcclRule.m NoAcclRule.h NoAcclPolicy.h
	@mkdir -p .theos
	clang -fobjc-arc -framework Foundation -o .theos/test_rule_model \
		tools/test_rule_model.m NoAcclRule.m
	@.theos/test_rule_model
