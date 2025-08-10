## Changelog

### v1.0.5
- CI: add contents: write permission and explicit token usage for release workflow (fix 403 on tag push)
- Meta: release verification tag; no functional code changes

### v1.0.4
- CI: remove duplicate release workflow block (stabilize automated releases)

### v1.0.3
- Feature: dynamic USER_AGENT derived from git tag or env override
- Installer: default install directory /opt/ticket-printer with FORCE_REPLACE option
- CI: introduce GitHub Release workflow (softprops/action-gh-release)
- Docs: README updates for /opt default & dynamic version explanation
- Meta: add CHANGELOG.md

### v1.0.2
- Docs: expanded README with channel/version instructions
- Installer: channel/version aware logic (stable/main/pinned version)

### v1.0.1
- User-agent bump & minor fixes

### v1.0.0
- Initial feature set: UUID persistence, environment gathering, logging, schema validation, basic installer
