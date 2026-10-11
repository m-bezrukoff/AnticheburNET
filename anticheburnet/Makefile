include $(TOPDIR)/rules.mk

PKG_NAME:=anticheburnet

ANTICHEBURNET_SOURCE_VERSION:=$(or $(ANTICHEBURNET_PACKAGE_VERSION),$(ANTICHEBURNET_VERSION))
ANTICHEBURNET_HAS_RELEASE_VERSION:=$(if $(filter dev,$(ANTICHEBURNET_SOURCE_VERSION)),,$(ANTICHEBURNET_SOURCE_VERSION))
ANTICHEBURNET_COMPILED_VERSION:=$(if $(ANTICHEBURNET_HAS_RELEASE_VERSION),$(ANTICHEBURNET_SOURCE_VERSION),$(or $(ANTICHEBURNET_SOURCE_VERSION),dev))
ANTICHEBURNET_RELEASE_VERSION_VALID:=$(if $(ANTICHEBURNET_HAS_RELEASE_VERSION),$(shell printf '%s\n' '$(ANTICHEBURNET_SOURCE_VERSION)' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' && printf '1'),1)

ifeq ($(ANTICHEBURNET_RELEASE_VERSION_VALID),)
$(error ANTICHEBURNET_PACKAGE_VERSION and ANTICHEBURNET_VERSION must use x.y.z format)
endif

PKG_VERSION:=$(or $(ANTICHEBURNET_HAS_RELEASE_VERSION),0.0.0)
PKG_RELEASE:=

PKG_MAINTAINER:=Max Bezrukov <73909358+m-bezrukoff@users.noreply.github.com>
PKG_LICENSE:=GPL-2.0-or-later

include $(INCLUDE_DIR)/package.mk

define Package/anticheburnet
	SECTION:=net
	CATEGORY:=Network
	DEPENDS:=+ca-bundle +kmod-inet-diag +kmod-netlink-diag +kmod-tun +curl +ucode +ucode-mod-fs +ucode-mod-uci +kmod-nft-tproxy +coreutils-base64 +bind-dig +nftables +kmod-nft-nat +ip-full
	CONFLICTS:=https-dns-proxy nextdns luci-app-passwall luci-app-passwall2
	TITLE:=AnticheburNET backend service
	URL:=https://github.com/m-bezrukoff/AnticheburNET
	PKGARCH:=all
	USERID:=anticheburnetbyedpi:anticheburnetbyedpi
endef

define Package/anticheburnet/description
	AnticheburNET VPN, proxy and policy routing service for OpenWrt
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/anticheburnet/prerm
#!/usr/bin/ucode

if (getenv("IPKG_INSTROOT") == null || getenv("IPKG_INSTROOT") == "")
	system("/usr/bin/anticheburnet package_prerm " + (ARGV[0] || "") + " >/dev/null 2>&1");

exit(0);
endef

define Package/anticheburnet/postinst
#!/bin/sh

[ -n "$${IPKG_INSTROOT}" ] && exit 0
ANTICHEBURNET_LIB=/usr/lib/anticheburnet ucode -L /usr/lib/anticheburnet /usr/lib/anticheburnet/config/migration.uc migrate || exit $$?
/usr/bin/anticheburnet package_postinst
endef

define Package/anticheburnet/conffiles
/etc/config/anticheburnet
endef

define Package/anticheburnet/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/anticheburnet $(1)/etc/init.d/anticheburnet

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/etc/config/anticheburnet $(1)/etc/config/anticheburnet

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/anticheburnet $(1)/usr/bin/anticheburnet

	$(INSTALL_DIR) $(1)/usr/lib/anticheburnet
	$(CP) ./files/usr/lib/. $(1)/usr/lib/anticheburnet/

	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(ANTICHEBURNET_COMPILED_VERSION)/g' $(1)/usr/lib/anticheburnet/core/constants.uc
endef

$(eval $(call BuildPackage,anticheburnet))
