"use strict";
"require view";
"require form";
"require baseclass";
"require uci";
"require ui";
"require view.anticheburnet.main as main";

// Global settings
"require view.anticheburnet.settings as settings";

// Sections
"require view.anticheburnet.section as section";
"require view.anticheburnet.happ as happ";

// Server
"require view.anticheburnet.server as server";

// Dashboard
"require view.anticheburnet.dashboard as dashboard";

// Monitoring
"require view.anticheburnet.monitoring as monitoring";

// Diagnostic
"require view.anticheburnet.diagnostic as diagnostic";

// Updates
"require view.anticheburnet.updates as updates";

const UCI_PACKAGE = main.ANTICHEBURNET_UCI_PACKAGE;

function renderSectionAdd(sectionRef, extra_class) {
  const el = form.GridSection.prototype.renderSectionAdd.apply(sectionRef, [
    extra_class,
  ]);
  const nameEl = el.querySelector(".cbi-section-create-name");

  ui.addValidator(
    nameEl,
    "uciname",
    true,
    (value) => {
      const button = el.querySelector(".cbi-section-create > .cbi-button-add");
      const uciconfig = sectionRef.uciconfig || sectionRef.map.config;

      if (!value) {
        button.disabled = true;
        return true;
      }

      if (uci.get(uciconfig, value)) {
        button.disabled = true;
        return _("Expecting: %s").format(_("unique UCI identifier"));
      }

      button.disabled = null;
      return true;
    },
    "blur",
    "keyup",
  );

  return el;
}

function getRuleEditButtonText() {
  const label = _("Edit rule action");

  return label === "Edit rule action" ? "Edit" : label;
}

function configureGridSection(sectionRef, type, title, addTitle) {
  sectionRef.anonymous = false;
  sectionRef.addremove = true;
  sectionRef.sortable = true;
  sectionRef.rowcolors = true;
  sectionRef.nodescriptions = true;
  sectionRef.modaltitle = function (section_id) {
    const label = uci.get(UCI_PACKAGE, section_id, "label");
    return section_id ? `${title}: ${label || section_id}` : addTitle;
  };
  sectionRef.sectiontitle = function (section_id) {
    return uci.get(UCI_PACKAGE, section_id, "label") || section_id;
  };
  sectionRef.renderSectionAdd = function (extra_class) {
    return renderSectionAdd(sectionRef, extra_class);
  };

  if (type === "section") {
    sectionRef.renderRowActions = function (section_id) {
      return form.TableSection.prototype.renderRowActions.call(
        this,
        section_id,
        getRuleEditButtonText(),
      );
    };
  }
}

function addRoutingStrategy(map, rulesSection) {
  const strategySection = map.section(
    form.NamedSection,
    "settings",
    "settings",
    _("Routing strategy"),
  );
  strategySection.addremove = false;
  strategySection.parentoption = rulesSection;

  const strategy = strategySection.option(
    form.ListValue,
    "routing_strategy",
    _("Select routing strategy"),
    _("Torrent traffic always goes directly."),
  );
  strategy.value(
    "happ",
    _("HAPP rules: all through the tunnel except exclusions"),
  );
  strategy.value(
    "selected",
    _("Direct by default, exceptions through the tunnel"),
  );
  strategy.value("tunnel", _("All through the tunnel"));
  strategy.default = "selected";
  strategy.rmempty = false;

  const target = strategySection.option(
    form.ListValue,
    "routing_section",
    _("Tunnel connection"),
    _(
      "Global tunnel strategies ignore section lists. In HAPP mode, manual domains of the tunnel connection bypass the tunnel.",
    ),
  );
  target.value("", _("First enabled connection"));
  target.depends("routing_strategy", "happ");
  target.depends("routing_strategy", "tunnel");
  target.rmempty = true;
  target.load = function (sectionId) {
    this.keylist = [];
    this.vallist = [];
    this.value("", _("First enabled connection"));
    uci.sections(UCI_PACKAGE, "section", (item) => {
      if (
        item.enabled !== "0" &&
        ["connection", "proxy", "outbound", "vpn"].includes(item.action)
      )
        this.value(item[".name"], item.label || item[".name"]);
    });
    return form.ListValue.prototype.load.call(this, sectionId);
  };

  const happDetails = strategySection.option(form.DummyValue, "_happ_status", _("HAPP rules and resources"));
  happDetails.depends("routing_strategy", "happ");
  happDetails.renderWidget = () => happ.createWidget();

  // Keep the normal form load/save lifecycle, but render these global options
  // inside the Sections tab on every refresh instead of creating another tab.
  const renderStrategy = strategySection.render.bind(strategySection);
  strategySection.render = () =>
    Promise.resolve(document.createDocumentFragment());
  const renderRules = rulesSection.render.bind(rulesSection);
  rulesSection.render = function () {
    return Promise.all([renderStrategy(), renderRules()]).then(
      ([options, rules]) => {
        const settingsNode = options.querySelector(
          '[data-section-id="settings"]',
        );
        if (settingsNode) settingsNode.removeAttribute("id");
        rules.insertBefore(options, rules.firstChild);
        return rules;
      },
    );
  };
}

const EntryPoint = {
  async render() {
    main.injectGlobalStyles();
    const uiCapabilities = {
      loaded: false,
      singBoxExtended: false,
      singBoxTiny: false,
      singBoxTailscale: true,
      zapretInstalled: false,
      zapret2Installed: false,
      byedpiInstalled: false,
      serverInboundsEnabledCount: -1,
    };
    let uiCapabilitiesPromise = null;
    let serverSectionRef = null;

    const applyUiCapabilities = function () {
      if (serverSectionRef) {
        server.applyServerCapabilities(serverSectionRef, uiCapabilities);
      }

      if (typeof window !== "undefined") {
        window.dispatchEvent(
          new CustomEvent(main.ANTICHEBURNET_ACTION_PROVIDERS_AVAILABILITY_EVENT, {
            detail: {
              zapretInstalled: uiCapabilities.zapretInstalled,
              zapret2Installed: uiCapabilities.zapret2Installed,
              byedpiInstalled: uiCapabilities.byedpiInstalled,
            },
          }),
        );
      }

      if (main.store && typeof main.store.set === "function") {
        const currentSystemInfo = main.store.get().diagnosticsSystemInfo;
        main.store.set({
          diagnosticsSystemInfo: {
            ...currentSystemInfo,
            providerInfoLoaded: true,
            sing_box_extended: uiCapabilities.singBoxExtended ? 1 : 0,
            sing_box_tiny: uiCapabilities.singBoxTiny ? 1 : 0,
            sing_box_tailscale: uiCapabilities.singBoxTailscale ? 1 : 0,
            zapret_installed: uiCapabilities.zapretInstalled ? 1 : 0,
            zapret2_installed: uiCapabilities.zapret2Installed ? 1 : 0,
            byedpi_installed: uiCapabilities.byedpiInstalled ? 1 : 0,
            server_inbounds_enabled_count:
              uiCapabilities.serverInboundsEnabledCount,
            zapret_version: uiCapabilities.zapretInstalled
              ? currentSystemInfo.zapret_version
              : "not installed",
            zapret2_version: uiCapabilities.zapret2Installed
              ? currentSystemInfo.zapret2_version
              : "not installed",
            byedpi_version: uiCapabilities.byedpiInstalled
              ? currentSystemInfo.byedpi_version
              : "not installed",
          },
        });
      }
    };

    const updateUiCapabilities = function (data) {
      uiCapabilities.loaded = true;
      uiCapabilities.singBoxExtended = Boolean(
        Number(data?.sing_box_extended) === 1,
      );
      uiCapabilities.singBoxTiny = Boolean(Number(data?.sing_box_tiny) === 1);
      uiCapabilities.singBoxTailscale =
        typeof data?.sing_box_tailscale === "undefined"
          ? true
          : Boolean(Number(data.sing_box_tailscale) === 1);
      uiCapabilities.zapretInstalled = Boolean(
        Number(data?.zapret_installed) === 1,
      );
      uiCapabilities.zapret2Installed = Boolean(
        Number(data?.zapret2_installed) === 1,
      );
      uiCapabilities.byedpiInstalled = Boolean(
        Number(data?.byedpi_installed) === 1,
      );
      const serverInboundsEnabledCount =
        typeof data?.server_inbounds_enabled_count !== "undefined"
          ? Number(data.server_inbounds_enabled_count)
          : -1;
      uiCapabilities.serverInboundsEnabledCount = Number.isFinite(
        serverInboundsEnabledCount,
      )
        ? serverInboundsEnabledCount
        : -1;

      applyUiCapabilities();

      return uiCapabilities;
    };

    const applyUiState = function (data) {
      const result = updateUiCapabilities(data?.capabilities || data || {});

      if (typeof main.applyUiStateToStore === "function" && data?.service) {
        main.applyUiStateToStore(data);
      } else if (
        main.store &&
        typeof main.store.set === "function" &&
        data?.service
      ) {
        main.store.set({
          servicesInfoWidget: {
            loading: false,
            failed: false,
            data: {
              singbox: Number(data.service.sing_box?.running) || 0,
              anticheburnetRunning: Number(data.service.anticheburnet?.running) || 0,
              anticheburnetEnabled: Number(data.service.anticheburnet?.enabled) || 0,
              anticheburnetStatus: data.service.anticheburnet?.status || "",
            },
          },
        });
      }

      return result;
    };

    const loadFallbackUiCapabilities = function () {
      return Promise.allSettled([
        main.AnticheburNETShellMethods.getServerCapabilities(),
        main.AnticheburNETShellMethods.checkZapretRuntime(),
        main.AnticheburNETShellMethods.checkZapret2Runtime(),
        main.AnticheburNETShellMethods.checkByedpiRuntime(),
        main.AnticheburNETShellMethods.checkInboundsConfig(),
      ]).then(
        ([
          serverCapabilitiesResult,
          zapretRuntimeResult,
          zapret2RuntimeResult,
          byedpiRuntimeResult,
          inboundsConfigResult,
        ]) => {
          const serverCapabilities =
            serverCapabilitiesResult.status === "fulfilled"
              ? serverCapabilitiesResult.value
              : null;
          const zapretRuntime =
            zapretRuntimeResult.status === "fulfilled"
              ? zapretRuntimeResult.value
              : null;
          const zapret2Runtime =
            zapret2RuntimeResult.status === "fulfilled"
              ? zapret2RuntimeResult.value
              : null;
          const byedpiRuntime =
            byedpiRuntimeResult.status === "fulfilled"
              ? byedpiRuntimeResult.value
              : null;
          const inboundsConfig =
            inboundsConfigResult.status === "fulfilled"
              ? inboundsConfigResult.value
              : null;

          return updateUiCapabilities({
            sing_box_extended:
              serverCapabilities?.success &&
              Number(serverCapabilities.data?.sing_box_extended) === 1
                ? 1
                : 0,
            sing_box_tiny:
              serverCapabilities?.success &&
              Number(serverCapabilities.data?.sing_box_tiny) === 1
                ? 1
                : 0,
            sing_box_tailscale:
              !serverCapabilities?.success ||
              typeof serverCapabilities.data?.sing_box_tailscale ===
                "undefined" ||
              Number(serverCapabilities.data?.sing_box_tailscale) === 1
                ? 1
                : 0,
            zapret_installed:
              zapretRuntime?.success &&
              Number(zapretRuntime.data?.zapret_installed) === 1
                ? 1
                : 0,
            zapret2_installed:
              zapret2Runtime?.success &&
              Number(zapret2Runtime.data?.zapret2_installed) === 1
                ? 1
                : 0,
            byedpi_installed:
              byedpiRuntime?.success &&
              Number(byedpiRuntime.data?.byedpi_installed) === 1
                ? 1
                : 0,
            server_inbounds_enabled_count:
              inboundsConfig?.success &&
              typeof inboundsConfig.data?.enabled_count !== "undefined"
                ? inboundsConfig.data.enabled_count
                : -1,
          });
        },
      );
    };

    const loadUiCapabilities = function () {
      if (uiCapabilities.loaded) {
        return Promise.resolve(uiCapabilities);
      }

      if (uiCapabilitiesPromise) {
        return uiCapabilitiesPromise;
      }

      uiCapabilitiesPromise = main.AnticheburNETShellMethods.getUiCapabilities()
        .then((response) => {
          if (!response?.success) {
            throw new Error("UI capabilities request failed");
          }

          return updateUiCapabilities(response.data);
        })
        .catch((error) => {
          console.warn("Failed to load AnticheburNET UI capabilities", error);
          return main.AnticheburNETShellMethods.getUiState()
            .then((response) => {
              if (!response?.success) {
                throw new Error("UI state request failed");
              }

              return applyUiState(response.data);
            })
            .catch((fallbackError) => {
              console.warn("Failed to load AnticheburNET UI state", fallbackError);
              return loadFallbackUiCapabilities();
            });
        })
        .finally(() => {
          uiCapabilitiesPromise = null;
        });

      return uiCapabilitiesPromise;
    };
    const anticheburnetMap = new form.Map(
      UCI_PACKAGE,
      _("AnticheburNET Settings"),
      _("Configuration for AnticheburNET service"),
    );
    anticheburnetMap.tabbed = true;
    const originalHandleSaveApply = anticheburnetMap.handleSaveApply;
    anticheburnetMap.handleSaveApply = function (ev, mode) {
      const refreshUiState = function () {
        main.AnticheburNETShellMethods.getUiState()
          .then((response) => {
            if (
              response?.success &&
              typeof main.applyUiStateToStore === "function"
            ) {
              main.applyUiStateToStore(response.data);
            }
          })
          .catch(() => null);
      };

      if (main.store && typeof main.store.set === "function") {
        const servicesInfoWidget = main.store.get().servicesInfoWidget;
        main.store.set({
          servicesInfoWidget: {
            ...servicesInfoWidget,
            data: {
              ...servicesInfoWidget.data,
              anticheburnetStatus: "reloading",
            },
          },
        });
      }

      return Promise.resolve(originalHandleSaveApply.call(this, ev, mode))
        .then((result) => {
          window.setTimeout(refreshUiState, 250);

          return result;
        })
        .catch((error) => {
          refreshUiState();

          throw error;
        });
    };

    const rulesSection = anticheburnetMap.section(
      form.GridSection,
      "section",
      _("Sections"),
      _("Drag rows to change priority. The rule at the top is checked first."),
    );
    configureGridSection(
      rulesSection,
      "section",
      _("Section"),
      _("Add a section"),
    );
    section.configureSectionSection(rulesSection, {
      loadActionProvidersAvailability: loadUiCapabilities,
    });
    section.createSectionContent(rulesSection);
    addRoutingStrategy(anticheburnetMap, rulesSection);

    const serverSection = anticheburnetMap.section(
      form.GridSection,
      "server",
      _("Servers"),
      _("Accept external proxy connections and route them with sing-box."),
    );
    configureGridSection(
      serverSection,
      "server",
      _("Server"),
      _("Add a server inbound"),
    );
    serverSectionRef = serverSection;
    server.configureServerSection(serverSection, {
      loadCapabilities: loadUiCapabilities,
    });
    server.createServerContent(serverSection, uiCapabilities);

    const settingsSection = anticheburnetMap.section(
      form.TypedSection,
      "settings",
      _("Settings"),
    );
    settingsSection.anonymous = true;
    settingsSection.addremove = false;
    settingsSection.cfgsections = function () {
      return ["settings"];
    };
    settings.createSettingsContent(settingsSection, uiCapabilities);

    const diagnosticSection = anticheburnetMap.section(
      form.TypedSection,
      "diagnostic",
      _("Diagnostics"),
    );
    diagnosticSection.anonymous = true;
    diagnosticSection.addremove = false;
    diagnosticSection.cfgsections = function () {
      return ["diagnostic"];
    };
    diagnostic.createDiagnosticContent(diagnosticSection);

    const dashboardSection = anticheburnetMap.section(
      form.TypedSection,
      "dashboard",
      _("Dashboard"),
    );
    dashboardSection.anonymous = true;
    dashboardSection.addremove = false;
    dashboardSection.cfgsections = function () {
      return ["dashboard"];
    };
    dashboard.createDashboardContent(dashboardSection);

    const monitoringSection = anticheburnetMap.section(
      form.TypedSection,
      "monitoring",
      _("Monitoring"),
    );
    monitoringSection.anonymous = true;
    monitoringSection.addremove = false;
    monitoringSection.cfgsections = function () {
      return ["monitoring"];
    };
    monitoring.createMonitoringContent(monitoringSection);

    const updatesSection = anticheburnetMap.section(
      form.TypedSection,
      "updates",
      _("Components"),
    );
    updatesSection.anonymous = true;
    updatesSection.addremove = false;
    updatesSection.cfgsections = function () {
      return ["updates"];
    };
    updates.createUpdatesContent(updatesSection);

    await loadUiCapabilities().catch(() => null);

    const rendered = await anticheburnetMap.render();
    main.coreService({
      waitForLogWatcherStart: loadUiCapabilities,
      logWatcherStartDelayMs: 5000,
    });

    return rendered;
  },
};

return view.extend(EntryPoint);
