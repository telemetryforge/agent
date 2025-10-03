<p align="center">
  <img src="extras/fluentdo-agent-logo.jpeg" alt="FluentDo Agent" height="200">
</p>

<p align="center">
  <a href="https://docs.fluent.do"><img src="https://img.shields.io/badge/docs-docs.fluent.do-blue" alt="Documentation"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
  <a href="https://github.com/FluentDo/agent/releases"><img src="https://img.shields.io/github/v/release/FluentDo/agent?sort=semver" alt="Release"></a>
  <a href="https://fluent.do/support"><img src="https://img.shields.io/badge/LTS-24%20months-green" alt="LTS"></a>
  <a href="https://join.slack.com/share/enQtOTU4MDk0MTQ0OTYzNi03MTY5MTc2Y2I0Y2JhY2QxNzc5MDNkNDdhNTRhNTgzNjkwMDc4Mzk1YTRhZWUzNTE4ZjM3OTljOTA4MzAxYjBl"><img src="https://img.shields.io/badge/slack-join-brightgreen" alt="Slack"></a>
</p>

## What is [FluentDo](https://fluent.do) Agent?

[FluentDo](https://fluent.do) Agent is a **stable, secure by default, OSS (Apache-licensed) downstream distribution of Fluent Bit** with predictable releases and long-term supported versions for 24 months.

## Support & Lifecycle

### Version Support Matrix

| Version | Release Date | Type | End of Support | Status |
|---------|-------------|------|----------------|--------|
| **[26.04](https://github.com/orgs/FluentDo/projects/4)** | Apr 2026 | LTS | Apr 2028 | 🟡 Planned |
| **[25.10](https://github.com/orgs/FluentDo/projects/3)** | Oct 2025 | LTS | Oct 2027 | 🟡 Planned |
| 25.07 | Jul 2025 | Regular | Jan 2026 | 🟢 Active |

### Release Schedule

| Release Type | Frequency | Description |
|-------------|-----------|-------------|
| **LTS Release** | Twice yearly (April, October) | Long-term support for 24 months |
| **Regular Release** | Quarterly | 6-month support cycle |
| **Security Updates** | Weekly | CVE patches and critical fixes |
| **Patch Release** | As needed | Bug fixes and minor updates |
| **Main Builds** | Weekly | Latest development builds from main branch |

---

### Why [FluentDo](https://fluent.do) Agent?

- ✅ **Smaller footprint** - Optimized for production deployments
  - Only production-essential plugins included
  - Size-focused builds with dead code elimination
  - IPO/LTO interprocedural optimization

- ✅ **Security-hardened by default** - Enterprise-grade security
  - FORTIFY_SOURCE and stack protection enabled
  - 17 vendor-specific plugins disabled by default
  - All remote interfaces disabled, authentication required
  - FIPS-compliant builds with OpenSSL in FIPS mode

- ✅ **24-month LTS support** - Predictable and reliable
  - Weekly security patches and CVE fixes
  - Quarterly releases with long-term stability
  - Daily security scans and vulnerability reporting

- ✅ **Advanced features** - Production-ready capabilities
  - Performant log deduplication - reduce costs by up to 40%
  - Log sampling processor for high-volume environments
  - AI-based filtering and routing
  - Native flattening for OpenSearch/Elasticsearch
  - Type safety with automatic conflict resolution

- ✅ **Battle-tested quality** - Continuous validation
  - Full integration and regression testing suite
  - Memory safety validation with Valgrind/AddressSanitizer
  - Performance benchmarks and regression testing

[Learn more about features →](https://docs.fluent.do/features)

---

## Quick Start

### Docker

```bash
docker run -v /var/log:/var/log ghcr.io/fluentdo/agent:main
```

### Package Installation

```bash
# Debian/Ubuntu
apt-get install fluentdo-agent

# RHEL/CentOS
yum install fluentdo-agent

# macOS
brew install fluentdo/tap/agent
```

### Building from Source

```bash
git clone https://github.com/FluentDo/agent.git
cd agent
./scripts/setup-code.sh
cd source/build
cmake ..
make
```

---

## Resources

- **[Documentation](https://docs.fluent.do)** - Complete documentation and guides
- **[Downloads](https://fluent.do/downloads)** - Pre-built packages and containers
- **[Release Notes](https://github.com/FluentDo/agent/releases)** - Version history and changelogs
- **[OSS Fluent Bit Docs](https://docs.fluentbit.io)** - Core documentation reference

---

## Community & Support

- **[Slack](https://join.slack.com/share/enQtOTU4MDk0MTQ0OTYzNi03MTY5MTc2Y2I0Y2JhY2QxNzc5MDNkNDdhNTRhNTgzNjkwMDc4Mzk1YTRhZWUzNTE4ZjM3OTljOTA4MzAxYjBl)** - Join our community chat
- **[GitHub Issues](https://github.com/FluentDo/agent/issues)** - Bug reports and feature requests
- **[Contributing Guide](CONTRIBUTING.md)** - How to contribute to the project
- **[Commercial Support](https://fluent.do)** - Enterprise support with SLA

---

## Security

### Reporting Security Issues

If you discover a potential security issue, **DO NOT** create a public GitHub issue. Instead, report it directly:

📧 **Email**: [security@fluent.do](mailto:security@fluent.do)

Please include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fixes (if any)

We follow responsible disclosure and will work with you to address issues promptly.

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).

## Copyright

Copyright © [FluentDo](https://fluent.do) Contributors. See [NOTICE](NOTICE) for details.

## Acknowledgments

[FluentDo](https://fluent.do) Agent is built on top of [Fluent Bit](https://fluentbit.io). We are grateful to the Fluent Bit community and all contributors who make this possible ❤️

---

<p align="center">
  <a href="https://fluent.do">Website</a> •
  <a href="https://docs.fluent.do">Docs</a> •
  <a href="https://twitter.com/fluentdo">Twitter</a> •
  <a href="https://fluent.do">Support</a>
</p>
