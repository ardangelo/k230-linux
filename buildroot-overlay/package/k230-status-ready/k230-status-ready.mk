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
endef

define K230_STATUS_READY_BUILD_DEB
	mkdir -p $(BINARIES_DIR)/deb
	$(INSTALL) -D -m 0755 $(@D)/k230-status-ready $(@D)/deb/usr/bin/k230-status-ready
	mkdir -p $(@D)/deb/etc/systemd/system/multi-user.target.wants
	ln -snf /etc/systemd/system/k230-status-ready.service $(@D)/deb/etc/systemd/system/multi-user.target.wants/k230-status-ready.service
	dpkg -b $(@D)/deb $(BINARIES_DIR)/deb/k230-status-ready.deb
endef

K230_STATUS_READY_POST_INSTALL_TARGET_HOOKS += K230_STATUS_READY_BUILD_DEB

$(eval $(generic-package))
