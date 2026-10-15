export THEOS_PACKAGE_SCHEME = rootless
THEOS ?= /opt/theos
TARGET := iphone:clang:27.1:15.0
ARCHS := arm64
include $(THEOS)/makefiles/common.mk
APPLICATION_NAME := NoAcclProbe
NoAcclProbe_FILES := main.m
NoAcclProbe_FRAMEWORKS := UIKit Foundation CoreMotion
NoAcclProbe_CFLAGS := -fobjc-arc
NoAcclProbe_RESOURCE_DIRS := Resources
include $(THEOS_MAKE_PATH)/application.mk
