# AnticheburNET 1.0.9

Subscription updates keep the dashboard visible during the sing-box restart. Previously measured latency remains visible for unchanged proxy links until fresh probes finish; changed and newly added servers do not inherit old measurements.

After a successful subscription update, the dashboard automatically tests latency for all groups using the updated node list. URLTest and Priority member measurements are preserved while probes run. Fresh results, including failed probes, replace the temporary cached values.

Subscription job status is checked immediately, removing the initial 1.5-second polling delay. Actual subscription download and sing-box reload time still depend on the provider and device.

Validation: 525 frontend tests, TypeScript, ESLint and the generated LuCI build passed locally. Backend, LuCI and Russian translation packages are rebuilt on GitHub; unchanged ARM64 components are reused from release 1.0.8 with SHA-256 verification.
