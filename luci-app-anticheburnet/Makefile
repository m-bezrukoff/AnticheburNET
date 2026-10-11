include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-anticheburnet

ANTICHEBURNET_SOURCE_VERSION:=$(or $(ANTICHEBURNET_PACKAGE_VERSION),$(ANTICHEBURNET_VERSION))
ANTICHEBURNET_HAS_RELEASE_VERSION:=$(if $(filter dev,$(ANTICHEBURNET_SOURCE_VERSION)),,$(ANTICHEBURNET_SOURCE_VERSION))
ANTICHEBURNET_COMPILED_VERSION:=$(if $(ANTICHEBURNET_HAS_RELEASE_VERSION),$(ANTICHEBURNET_SOURCE_VERSION),$(or $(ANTICHEBURNET_SOURCE_VERSION),dev))
ANTICHEBURNET_RELEASE_VERSION_VALID:=$(if $(ANTICHEBURNET_HAS_RELEASE_VERSION),$(shell printf '%s\n' '$(ANTICHEBURNET_SOURCE_VERSION)' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$$' && printf '1'),1)

ifeq ($(ANTICHEBURNET_RELEASE_VERSION_VALID),)
$(error ANTICHEBURNET_PACKAGE_VERSION and ANTICHEBURNET_VERSION must use x.y.z format)
endif

PKG_VERSION:=$(or $(ANTICHEBURNET_HAS_RELEASE_VERSION),0.0.0)
PKG_RELEASE:=
PKG_PO_VERSION:=$(PKG_VERSION)

LUCI_TITLE:=LuCI AnticheburNET app
LUCI_DEPENDS:=+luci-base +anticheburnet
LUCI_PKGARCH:=all
LUCI_LANG.ru:=Русский (Russian)
LUCI_LANG.en:=English
LUCI_MAINTAINER:=Max Bezrukov <73909358+m-bezrukoff@users.noreply.github.com>
LUCI_DESCRIPTION:=LuCI interface for AnticheburNET VPN, proxy and policy routing
LUCI_MINIFY_JS:=0

PKG_LICENSE:=GPL-2.0-or-later
LUCI_LANGUAGES:=en ru

define Build/Prepare/$(PKG_NAME)
	sed -i -e 's/__COMPILED_VERSION_VARIABLE__/$(ANTICHEBURNET_COMPILED_VERSION)/g' $(PKG_BUILD_DIR)/htdocs/luci-static/resources/view/anticheburnet/main.js
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
