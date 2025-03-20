SHARP_DRM_VERSION = 1.5
SHARP_DRM_BASE = $(realpath $(TOPDIR))"/package/sharp-drm"
SHARP_DRM_SITE = $(SHARP_DRM_BASE)/module
SHARP_DRM_SITE_METHOD = local

SHARP_DRM_INSTALL_IMAGES = YES
SHARP_DRM_MODULE_SUBDIRS = .

define SHARP_DRM_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(SHARP_DRM_BASE)/init/S01sharpdrm $(TARGET_DIR)/etc/init.d/;
endef

$(eval $(kernel-module))
$(eval $(generic-package))
