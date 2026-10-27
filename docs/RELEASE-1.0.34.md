# AnticheburNET 1.0.34

The daily 03:00 subscription update now retries temporary network failures up to three times, waiting 30 seconds between attempts. Each attempt has a fresh download window of up to 15 seconds. A successful attempt stops the retries; an error is reported only after the initial request and all three retries fail. Existing working subscription data is preserved on failure.

Transport failures report the curl exit code instead of incorrectly claiming that no compatible subscription request profile exists. HTTP and subscription-format failures do not trigger delayed network retries. Manual updates retain their fast two-second download budget, and service startup does not wait through the daily retry pauses.

Dashboard no longer displays the DB-IP geolocation link. The bundled database attribution remains available in the package and documentation.

Backend, LuCI and Russian translations are rebuilt as APK and IPK packages. Unchanged ARM64 components are reused from release 1.0.33.
