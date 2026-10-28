# License scope

The root [MIT license](LICENSE) covers the backend distributed in this repository:
the HTTP gateway, generic Pages delivery adapter, read-only Edge asset gateway, database migrations, security tests, and operational scripts. The adapter is hosting infrastructure, not the proprietary application interface.

The proprietary frontend source lives in the ignored `frontend/` workspace. Its
compiled runtime assets are published separately to the database, not included in
this repository or the backend’s MIT distribution. Third-party frontend packages
retain their own licenses; the release packager includes their notices.

This boundary does not revoke any license previously granted for already
published material. Database delivery is not source-code secrecy: browsers still
receive the HTML, CSS, and JavaScript required to display the site.
