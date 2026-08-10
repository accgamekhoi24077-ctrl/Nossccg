TARGET := iphone:clang:latest:7.0
INSTALL_TARGET_PROCESSES = FreeFire
ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Bypass
Bypass_FILES = Tweak.xm
Bypass_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk