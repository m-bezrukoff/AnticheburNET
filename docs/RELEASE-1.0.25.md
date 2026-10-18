# AnticheburNET 1.0.25

The LuCI interface now uses a consistent compact layout across Dashboard, Sections, Servers, Settings, Diagnostics, Monitoring, Components and editing dialogs. Panels, tables, controls, spacing and status indicators share the same visual language and follow the active light or dark theme. Narrow layouts stack form fields and keep wide technical tables scrollable inside their own bounds.

The HAPP inspector now separates profile metadata, routing rules and resource readiness. Domain and IP rules are shown in two columns, empty actions stay compact, and resource sources and timestamps are secondary to their status. Automatic refresh preserves expanded groups, keyboard focus and rule-list scrolling, including interaction while a read is in progress. Subscription values are rendered as text, and saved configuration remains distinct from applied runtime state.

HAPP geodata downloads now retry transient failures through the selected connection. Retries remain bounded and preserve the previous database and runtime configuration on failure. Download errors now record the exit code in resource status and the service log for diagnosis after a failed cold start.

Release checks and component downloads also retry transient HTTP and connection-refused failures. Curl uses the explicit selected proxy or direct connection and ignores ambient curl configuration and proxy bypass settings.

Startup now allows up to 30 seconds for sing-box to reach its required stable running state, instead of 10 seconds. The existing process age, listener and routing checks remain required.

New configurations and configurations without an explicit DNS strategy now default to IPv4 only. Explicitly configured DNS strategies are preserved. The default is consistent across LuCI, validation, generated configuration and reload signatures.

Regression checks cover failed download preservation, proxy and direct transport selection, partial response cleanup, and release update behavior.

Application, LuCI and Russian translation packages are rebuilt. ARM64 component binaries are unchanged from 1.0.24.
