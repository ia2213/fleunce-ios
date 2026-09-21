# Security review — September 12, 2026

No usable credentials were found in the audited public source or Git history. The review found and fixed seven issues involving request admission, backup imports and key-removal feedback. Backend fixes are deployed from `0b2cf65`; the signed iPhone update is installed. This review does not establish that Fleunce is free of every vulnerability.

## Scope and secret checks

The initial scan covered app revision `b45d31e` (9 commits, 124 tracked files) and website revision `ab20d41` (7 commits, 28 tracked files), after fetching remote branches and tags. Neither repository had pull requests at that checkpoint. Eight Gitleaks 8.30.1 scans covered reachable history, tracked snapshots, all locally stored Git blobs, and the pending security changes. All returned zero findings. Public CI secret scans also passed for app `0b2cf65` and website `85d7196`.

Supplemental matches were disposable database credentials, environment placeholders and deliberately invalid test fixtures. Google's OAuth client ID, bundle ID and callback scheme are public identifiers; they do not grant access to an account. No live provider key, private signing key, database password, account token or private deployment dump was identified. Ignored local credential files were not included in the scan, and phone credentials were not retrieved.

## Corrections

| Area | Issue and correction |
| --- | --- |
| API routing | Encoded route names could miss raw-path admission checks. Checks now use Fastify's matched route definition, including webhook body parsing. Identity and bearer verification were still enforced by the affected handlers. |
| Shared quotas | Requests already rejected for one network consumed global allowances. Rejected requests now undo those increments within the locked transaction. |
| Proxy identity | Public metadata reads shared Caddy's socket address for throttling. They now use an authenticated, hashed client-network identity; Caddy supplies and overwrites the required headers. |
| Backup file size | Import loaded the entire selected file before enforcing its limit. File reads are now bounded before allocation and during reading. |
| Backup values | Extreme numeric and date values could crash later display or calculations. Import now validates them before changing stored history. |
| Backup merge | Two individually valid archives could combine into one that failed to reopen. The complete merged archive is validated before replacing local history. |
| Key removal | Settings reported success when Keychain deletion failed. It now checks the result and preserves the error state. |

The backup issues require a user to import a malformed file. They did not provide remote access to the phone. The server findings affected admission and availability; this review found no cross-account disclosure, SQL injection or attacker-directed outbound request in the traced paths.

## Verification

- **77 backend tests** passed against PostgreSQL 17, including concurrent quota boundaries, encoded routes and signed webhook replay. Typechecking and the container build passed.
- **60 Swift Core tests** and **two focused UI checks** passed. Tests reproduced unsafe imported values before the fix. The updated personal build was installed without uninstalling or changing its bundle/team. The following launch was blocked because the phone was locked.
- Live HTTPS checks passed for health, readiness, pricing and Google-provider discovery. Ordinary and encoded anonymous account requests returned 401; malformed exchange returned 400. Waitlist preflight returned 204 and malformed submissions returned 400. Wallet, checkout, webhooks, trials and hosted speech remain behind their 503 gate.
- The user confirmed Google login. A private database check confirmed one account, Google identity, empty wallet and valid hashed session using counts and booleans only.
- `npm audit` reported zero known advisories across 119 locked packages. The website's two first-party scripts were manually reviewed; no actionable XSS or telemetry was found. Sensitive-file URL probes returned 404.
- [CodeQL setup](https://github.com/Chuloo/fleunce/actions/runs/34701612333) completed for Swift, JavaScript/TypeScript, Python and GitHub Actions on `b45d31e`. Fourteen alerts were individually reviewed: six involved trusted operator inputs or test assertions, and eight did not recognize the custom rate-limit hook. Their false-positive dispositions include individual explanations. The separate manual admission defects above were fixed and deployed; no blanket scanning rule was suppressed.

## Ongoing protection and limits

Both public repositories have GitHub secret scanning, push protection, private vulnerability reporting, dependency alerts, security updates and checksum-pinned full-history secret-scan workflows. CodeQL is configured for the app repository with extended queries and remote/local input analysis. The website's compiled assets were not recognized by CodeQL default setup; its JavaScript review was manual.

The review did not independently rebuild or audit WebRTC's precompiled native dependency, audit container/OS packages, perform destructive production tests, or establish resistance to a distributed flood. Apple authorization, real hosted speech, live purchases and the remaining device session/deletion lifecycle require separate release checks. Undisclosed vulnerabilities and patterns missed by the scanners remain possible.

Report new findings through the repository's private vulnerability reporting flow or [hi@hackmamba.io](mailto:hi@hackmamba.io). Do not include live credentials or another person's data.
