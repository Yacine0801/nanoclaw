# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-04-04

### Added
- Multi-agent architecture: 4 agents (Botti, Sam, Thais, Alan) on separate instances
- Google Chat integration via Chat App + Firestore gateway
- Gmail webhook integration (Pub/Sub -> Botti Voice -> Firestore -> NanoClaw)
- Email filtering: skip newsletters, noreply, marketing before agent spawn
- Botti Voice: unified memory from NanoClaw CLAUDE.md, agent selector (Botti/Sam/Thais)
- Dashboard: real-time monitoring on port 3100
- create-agent.sh: automated agent creation in one command
- deploy.sh: build + distribute dist/ to all instances
- Health endpoint: GET /health on credential proxy port
- Prometheus metrics: /metrics endpoint with counters and gauges
- Circuit breaker on credential proxy (5 failures -> 503, 60s reset)
- IPC rate limiting: max 20 active tasks per group
- Zod environment validation at startup
- Log rotation script (7-day retention, 14-day for container logs)
- Gmail send safety: draft + notification for external recipients, direct only to allowlisted
- Google Chat access rules: per-user permissions (Eline/Ahmed/Yacine)
- 461 tests (unit + integration)
- Architecture diagrams (docs/ARCHITECTURE.md)
- Technical overview for Ahmed (docs/TECHNICAL-OVERVIEW.md)
- Botler 360 SAS proprietary license

### Changed
- index.ts split into 4 modules (state.ts, message-processor.ts, channel-manager.ts, index.ts)
- Magic numbers centralized in constants.ts
- dist/ isolated per instance (no more shared symlinks)
- Poll intervals configurable via environment variables
- Mount allowlist hot-reload (60s TTL cache)
- Session IDs redacted in structured logs
- Gmail polling reduced to 5min when webhook active (was 60s)
- Proxy bind fallback changed from 0.0.0.0 to 127.0.0.1 on Linux

### Fixed
- Container .gmail-mcp mount now read-only (security)
- gws mount restored to writable (token refresh needed)
- Remote Control requires PIN (disabled if not set)
- Chat gateway admin endpoint requires API key
- Gmail send allowlist moved to external config file
- Anti-spam state cleanup (7-day TTL)
- GroupQueue cleanup method for stale entries
- spaceIdToName map capped at 500 entries
- Type safety: replaced `any` casts with proper `unknown` narrowing
- Backoff calculation extracted to shared utility

### Security
- Credential proxy isolation (containers never see real API keys)
- Mount security: blocked patterns (.ssh, .env, credentials)
- Per-group IPC namespaces prevent cross-contamination
- Session ID redaction in logs
- Circuit breaker prevents API spam during outages

## [1.2.15] - 2026-03-15

### Fixed
- Security hardening, code quality audit, ops infrastructure
- Media download and barge-in support
- Gmail/Calendar webhooks
- Anti-spam improvements
- Email reply routing

### Added
- Agent-hub orchestrator
- Botti Voice send_email capability

## [1.2.14] - 2026-02-20

### Added
- Remote control command for host-level Claude Code access

### Fixed
- Auto-accept remote-control prompt to prevent immediate exit
- KillMode=process so remote-control survives restarts

## [1.2.13] - 2026-02-10

### Changed
- Bumped claude-agent-sdk to ^0.2.76

## [1.2.12] - 2026-01-28

### Added
- Container environment isolation via credential proxy
- /compact skill for manual context compaction

## [1.2.11] - 2026-01-20

### Fixed
- Close task container promptly when agent uses IPC-only messaging

### Added
- WhatsApp reactions skill (emoji reactions + status tracker)
- Image vision skill for WhatsApp
- PDF reader skill

## [1.2.10] - 2026-01-15

### Fixed
- LIMIT added to unbounded message history queries

## [1.2.9] - 2026-01-12

### Added
- Timezone-aware context injection for agent prompts

### Fixed
- add-voice-transcription skill drops WhatsApp registerChannel call

## [1.2.8] - 2026-01-10

### Fixed
- Correct misleading send_message tool description for scheduled tasks

## [1.2.7] - 2026-01-08

### Added
- update_task tool and return task ID from schedule_task

## [1.2.6] - 2026-01-05

### Changed
- Updated claude-agent-sdk to 0.2.68

## [1.2.5] - 2026-01-03

### Fixed
- Format src/index.ts to pass CI prettier check

## [1.2.4] - 2026-01-02

### Fixed
- Renamed _chatJid to chatJid in onMessage callback

## [1.2.3] - 2025-12-28

### Added
- Sender allowlist for per-chat access control

## [1.2.2] - 2025-12-25

### Fixed
- Atomic claim prevents scheduled tasks from executing twice

### Added
- use-local-whisper skill package

## [1.2.1] - 2025-12-20

### Changed
- Multi-channel architecture refactored

### Added
- Breaking changes check after update-nanoclaw
- Auto-initialize skills system when applying first skill

### Fixed
- Shadow env in container
- Prevent command injection in setup verify PID check

## [1.1.6] - 2025-12-15

### Fixed
- Normalize wrapped WhatsApp messages before reading content

## [1.1.5] - 2025-12-12

### Fixed
- Normalize wrapped WhatsApp messages before reading content

## [1.1.4] - 2025-12-08

### Added
- Third-party model support

## [1.1.3] - 2025-12-01

### Changed
- CI optimization, logging improvements, and codebase formatting

## [1.1.2] - 2025-11-25

### Fixed
- Error handling and tests for WA Web version fetch

## [1.1.1] - 2025-11-20

### Fixed
- Use fetchLatestWaWebVersion to prevent 405 connection failures

## [1.1.0] - 2025-11-15

### Added
- Official Qodo skills and codebase intelligence
- /update skill for pulling upstream changes
- Skills engine v0.1 + multi-channel infrastructure

### Changed
- README rewritten for broader audience and updated feature set

## [1.0.0] - 2025-10-01

### Added
- Initial NanoClaw release: personal Claude assistant via WhatsApp
- Containerized agent execution with Apple Container
- Built-in scheduler with group-scoped tasks
- Per-group queue, SQLite state, graceful shutdown
- Mount security allowlist for external directory access
- Per-group session isolation
- Setup skill with scripted steps
- Skills as branches, channels as forks architecture
