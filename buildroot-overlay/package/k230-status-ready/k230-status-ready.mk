################################################################################
#
# k230-status-ready
#
################################################################################
K230_STATUS_READY_SITE = $(realpath $(TOPDIR))/package/k230-status-ready
K230_STATUS_READY_SITE_METHOD = local
K230_STATUS_READY_INSTALL_TARGET = YES
define K230_STATUS_READY_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/k230-status-ready $(TARGET_DIR)/usr/bin/k230-status-ready
	$(INSTALL) -D -m 0755 $(@D)/init/S99k230-status-ready $(TARGET_DIR)/etc/init.d/S99k230-status-ready
endef
$(eval $(generic-package))
