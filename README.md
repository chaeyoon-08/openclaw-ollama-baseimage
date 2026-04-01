# openclaw-base

OpenClaw + Ollama 기반 Telegram AI 비서 컨테이너 이미지.
gcube 워크로드에 배포하여 환경변수만 설정하면 즉시 사용 가능.

---

<!-- OPENCLAW_VERSION_START -->
## OpenClaw 버전 정보

> 이미지 빌드 시 자동 갱신됩니다.

| 항목 | 내용 |
|---|---|
| 설치 버전 | `2026.3.31` |
| 빌드 날짜 | 2026-04-01 |

### 릴리즈 노트

### Breaking

- Nodes/exec: remove the duplicated `nodes.run` shell wrapper from the CLI and agent `nodes` tool so node shell execution always goes through `exec host=node`, keeping node-specific capabilities on `nodes invoke` and the dedicated media/location/notify actions.
- Plugin SDK: deprecate the legacy provider compat subpaths plus the older bundled provider setup and channel-runtime compatibility shims, emit migration warnings, and keep the current documented `openclaw/plugin-sdk/*` entrypoints plus local `api.ts` / `runtime-api.ts` barrels as the forward path ahead of a future major-release removal.
- Skills/install and Plugins/install: built-in dangerous-code `critical` findings and install-time scan failures now fail closed by default, so plugin installs and gateway-backed skill dependency installs that previously succeeded may now require an explicit dangerous override such as `--dangerously-force-unsafe-install` to proceed.
- Gateway/auth: `trusted-proxy` now rejects mixed shared-token configs, and local-direct fallback requires the configured token instead of implicitly authenticating same-host callers. Thanks @zhangning-agent, @jacobtomlinson, and @vincentkoc.
- Gateway/node commands: node commands now stay disabled until node pairing is approved, so device pairing alone is no longer enough to expose declared node commands. (#57777) Thanks @jacobtomlinson.
- Gateway/node events: node-originated runs now stay on a reduced trusted surface, so notification-driven or node-triggered flows that previously relied on broader host/session tool access may need adjustment. (#57691) Thanks @jacobtomlinson.

### Changes

- ACP/plugins: add an explicit default-off ACPX plugin-tools MCP bridge config, document the trust boundary, and harden the built-in bridge packaging/logging path so global installs and stdio MCP sessions work reliably. (#56867) Thanks @joe2643.
- Agents/LLM: add a configurable idle-stream timeout for embedded runner requests so stalled model streams abort cleanly instead of hanging until the broader run timeout fires. (#55072) Thanks @liuy.
- Agents/MCP: materialize bundle MCP tools with provider-safe names (`serverName__toolName`), support optional `streamable-http` transport selection plus per-server connection timeouts, and preserve real tool results from aborted/error turns unless truncation explicitly drops them. (#49505) Thanks @ziomancer.
- Android/notifications: add notification-forwarding controls with package filtering, quiet hours, rate limiting, and safer picker behavior for forwarded notification events. (#40175) Thanks @nimbleenigma.
- Background tasks: turn tasks into a real shared background-run control plane instead of ACP-only bookkeeping by unifying ACP, subagent, cron, and background CLI execution under one SQLite-backed ledger, routing detached lifecycle updates through the executor seam, adding audit/maintenance/status visibility, tightening auto-cleanup and lost-run recovery, improving task awareness in internal status/tool surfaces, and clarifying the split between heartbeat/main-session automation and detached scheduled runs. Thanks @mbelinky and @vincentkoc.
- Background tasks: add the first linear task flow control surface with `openclaw flows list|show|cancel`, keep manual multi-task flows separate from one-task auto-sync flows, and surface doctor recovery hints for obviously orphaned or broken flow/task linkage. Thanks @mbelinky and @vincentkoc.
- Channels/QQ Bot: add QQ Bot as a bundled channel plugin with multi-account setup, SecretRef-aware credentials, slash commands, reminders, and media send/receive support. (#52986) Thanks @sliverp.
- Diffs: skip unused viewer-versus-file SSR preload work so `diffs` view-only and file-only runs do less render work while keeping mode outputs aligned. (#57909) thanks @gumadeiras.
- Tasks: add a minimal SQLite-backed task flow registry plus task-to-flow linkage scaffolding, so orchestrated work can start gaining a first-class parent record without changing current task delivery behavior. Thanks @mbelinky and @vincentkoc.
- Tasks: persist blocked state on one-task task flows and let the same flow reopen cleanly on retry, so blocked detached work can carry a parent-level reason and continue without fragmenting into a new job. Thanks @mbelinky and @vincentkoc.
- Tasks: route one-task ACP and subagent updates through a parent task-flow owner context, so detached work can emerge back through the intended parent thread/session instead of speaking only as a raw child task. Thanks @mbelinky and @vincentkoc.
- LINE/outbound media: add LINE image, video, and audio outbound sends on the LINE-specific delivery path, including explicit preview/tracking handling for videos while keeping generic media sends on the existing image-only route. (#45826) Thanks @masatohoshino.
- Matrix/history: add optional room history context for Matrix group triggers via `channels.matrix.historyLimit`, with per-agent watermarks and retry-safe snapshots so failed trigger retries do not drift into newer room messages. (#57022) thanks @chain710.
- Matrix/network: add explicit `channels.matrix.proxy` config for routing Matrix traffic through an HTTP(S) proxy, including account-level overrides and matching probe/runtime behavior. (#56931) thanks @patrick-yingxi-pan.
- Matrix/streaming: add draft streaming so partial Matrix replies update the same message in place instead of sending a new message for each chunk. (#56387) Thanks @jrusz.
- Matrix/threads: add per-DM `threadReplies` overrides and keep thread session isolation aligned with the effective room or DM thread policy from the triggering message onward. (#57995) thanks @teconomix.
- MCP: add remote HTTP/SSE server support for `mcp.servers` URL configs, including auth headers and safer config redaction for MCP credentials. (#50396) Thanks @dhananjai1729.
- Memory/QMD: add per-agent `memorySearch.qmd.extraCollections` so agents can opt into cross-agent session search without flattening every transcript collection into one shared QMD namespace. Thanks @vincentkoc.
- Microsoft Teams/member info: add a Graph-backed member info action so Teams automations and tools can resolve channel member details directly from Microsoft Graph. (#57528) Thanks @sudie-codes.
- Nostr/inbound DMs: verify inbound event signatures before pairing or sender-authorization side effects, so forged DM events no longer create pairing requests or trigger reply attempts. Thanks @smaeljaish771 and @vincentkoc.
- OpenAI/Responses: forward configured `text.verbosity` across Responses HTTP and WebSocket transports, surface it in `/status`, and keep per-agent verbosity precedence aligned with runtime behavior. (#47106) Thanks @merc1305 and @vincentkoc.
- Pi/Codex: add native Codex web search support for embedded Pi runs, including config/docs/wizard coverage and managed-tool suppression when native Codex search is active. (#46579) Thanks @Evizero.
- Slack/exec approvals: add native Slack approval routing and approver authorization so exec approval prompts can stay in Slack instead of falling back to the Web UI or terminal. Thanks @vincentkoc.
- TTS: Add structured provider diagnostics and fallback attempt analytics. (#57954) Thanks @joshavant.
- WhatsApp/reactions: agents can now react with emoji on incoming WhatsApp messages, enabling more natural conversational interactions like acknowledging a photo with ❤️ instead of typing a reply. Thanks @mcaxtr.
- Agents/BTW: force `/btw` side questions to disable provider reasoning so Anthropic adaptive-thinking sessions stop failing with `No BTW response generated`. Fixes #55376. Thanks @Catteres and @vincentkoc.
- CLI/onboarding: reset the remote gateway URL prompt to the safe loopback default after declining a discovered endpoint, so onboarding does not keep a previously rejected remote URL. (#57828)
- Agents/exec defaults: honor per-agent `tools.exec` defaults when no inline directive or session override is present, so configured exec host, security, ask, and node settings actually apply. (#57689)
- Sandbox/networking: sanitize SSH subprocess env vars through the shared sandbox policy and route marketplace archive downloads plus Ollama discovery, auth, and pull requests through the guarded fetch path so sandboxed execution and remote fetches follow the repo's trust boundaries. (#57848, #57850)

### Fixes

- Slack: stop retry-driven duplicate replies when draft-finalization edits fail ambiguously, and log configured allowlisted users/channels by readable name instead of raw IDs.
- Agents/OpenAI Responses: normalize raw bundled MCP tool schemas on the WebSocket/Responses path so bare-object, object-ish, and top-level union MCP tools no longer get rejected by OpenAI during tool registration. (#58299) Thanks @yelog.
- ACP/security: replace ACP's dangerous-tool name override with semantic approval classes, so only narrow readonly reads/searches can auto-approve while indirect exec-capable and control-plane tools always require explicit prompt approval. Thanks @vincentkoc.
- ACP/sessions_spawn: register ACP child runs for completion tracking and lifecycle cleanup, and make registration-failure cleanup explicitly best-effort so callers do not assume an already-started ACP turn was fully aborted. (#40885) Thanks @xaeon2026 and @vincentkoc.
- ACP/tasks: mark cleanly exited ACP runs as blocked when they end on deterministic write or authorization blockers, and wake the parent session with a follow-up instead of falsely reporting success.
- ACPX/runtime: derive the bundled ACPX expected version from the extension package metadata instead of hardcoding a separate literal, so plugin-local ACPX installs stop drifting out of health-check parity after version bumps. (#49089) Thanks @jiejiesks and @vincentkoc.
- Agents/Anthropic failover: treat Anthropic `api_error` payloads with `An unexpected error occurred while processing the response` as transient so retry/fallback can engage instead of surfacing a terminal failure. (#57441) Thanks @zijiess and @vincentkoc.
- Agents/compaction: keep late compaction-retry completions from double-resolving finished compaction futures, so interrupted or timed-out compactions stop surfacing spurious second-completion races. (#57796) Thanks @joshavant.
- Agents/disabled providers: make disabled providers disappear from default model selection and embedded provider fallback, while letting explicitly pinned disabled providers fail with a clear config error instead of silently taking traffic. (#57735) Thanks @rileybrown-dev and @vincentkoc.
- Agents/OAuth output: force exec-host OAuth output readers through the gateway fs policy so embedded gateway runs stop crashing when provider auth writes land outside the current sandbox workspace. (#58249) Thanks @joshavant.
- Agents/system prompt: fix `agent.name` interpolation in the embedded runtime system prompt and make provider/model fallback text reflect the effective runtime selection after start. (#57625) Thanks @StllrSvr and @vincentkoc.
- Android/device info: read the app's version metadata from the package manager instead of hidden APIs so Android 15+ onboarding and device info no longer fail to compile or report placeholder values. (#58126) Thanks @L3ER0Y.
- Android/pairing: stop appending duplicate push receiver entries to `gateway-service.conf` on repeated QR pairing and keep push registration bounded to the current successful pairing, so Android push delivery stays healthy across re-pair and token rotation. (#58256) Thanks @surrealroad.
- App install smoke: pin the latest-release lookup to `latest`, cache the first stable install version across the rerun, and relax prerelease package assertions so the Parallels smoke lane can validate stable-to-main upgrades even when `beta` moves ahead or the guest starts from an older stable. (#58177) Thanks @vincentkoc.
- Auth/profiles: keep the last successful config load in memory for the running process and refresh that snapshot on successful writes/reloads, so hot paths stop reparsing `openclaw.json` between watcher-driven swaps.
- Config/SecretRef + Control UI: harden SecretRef redaction round-trip restore, block unsafe raw fallback (force Form mode when raw is unavailable), and preflight submitted-config SecretRefs before config write RPC persistence. (#58044) Thanks @joshavant.
- Config/Telegram: migrate removed `channels.telegram.groupMentionsOnly` into `channels.telegram.groups[\"*\"].requireMention` on load so legacy configs no longer crash at startup. (#55336) thanks @jameslcowan.
- Config/update: stop `openclaw doctor` write-backs from persisting plugin-injected channel defaults, so `openclaw update` no longer seeds config keys that later break service refresh validation. (#56834) Thanks @openperf.
- Control UI/agents: auto-load agent workspace files on initial Files panel open, and populate overview model/workspace/fallbacks from effective runtime agent metadata so defaulted models no longer show as `Not set`. (#56637) Thanks @dxsx84.
- Control UI/slash commands: make `/steer` and `/redirect` work from the chat command palette with visible pending state for active-run `/steer`, correct redirected-run tracking, and a single canonical `/steer` entry in the command menu. (#54625) Thanks @fuller-stack-dev.
- Cron/announce: preserve all deliverable text payloads for announce mode instead of collapsing to the last chunk, so multi-line cron reports deliver in full to Telegram forum topics.
- Cron/isolated sessions: carry the full live-session provider, model, and auth-profile selection across retry restarts so cron jobs with model overrides no longer fail or loop on mid-run model-switch requests. (#57972) Thanks @issaba1.
- Diffs/config: preserve schema-shaped plugin config parsing from `diffsPluginConfigSchema.safeParse()`, so direct callers keep `defaults` and `security` sections instead of receiving flattened tool defaults. (#57904) Thanks @gumadeiras.
- Diffs: fall back to plain text when `lang` hints are invalid during diff render and viewer hydration, so bad or stale language values no longer break the diff viewer. (#57902) Thanks @gumadeiras.
- Discord/voice: enforce the same guild channel and member allowlist checks on spoken voice ingress before transcription, so joined voice channels no longer accept speech from users outside the configured Discord access policy. Thanks @cyjhhh and @vincentkoc.
- Docker/setup: force BuildKit for local image builds (including sandbox image builds) so `./docker-setup.sh` no longer fails on `RUN --mount=...` when hosts default to Docker's legacy builder. (#56681) Thanks @zhanghui-china.
- Docs/anchors: fix broken English docs links and make Mint anchor audits run against the English-source docs tree. (#57039) thanks @velvet-shark.
- Doctor/plugins: skip false Matrix legacy-helper warnings when no migration plans exist, and keep bundled `enabledByDefault` plugins in the gateway startup set. (#57931) Thanks @dinakars777.
- Exec approvals/macOS: unwrap `arch` and `xcrun` before deriving shell payloads and allow-always patterns, so wrapper approvals stay bound to the carried command instead of the outer carrier. Thanks @tdjackey and @vincentkoc.
- Exec approvals: unwrap `caffeinate` and `sandbox-exec` before persisting allow-always trust so later shell payload changes still require a fresh approval. Thanks @tdjackey and @vincentkoc.
- Exec/approvals: infer Discord and Telegram exec approvers from existing owner config when `execApprovals.approvers` is unset, extend the default approval window to 30 minutes, and clarify approval-unavailable guidance so approvals do not appear to silently disappear.
- Pi/TUI: flush message-boundary replies at `message_end` so turns stop looking stuck until the next nudge when the final reply was already ready. Thanks @vincentkoc.
- Exec/approvals: keep `awk` and `sed` family binaries out of the low-risk `safeBins` fast path, and stop doctor profile scaffolding from treating them like ordinary custom filters. Thanks @vincentkoc.
- Exec/env: block proxy, TLS, and Docker endpoint env overrides in host execution so request-scoped commands cannot silently reroute outbound traffic or trust attacker-supplied certificate settings. Thanks @AntAISecurityLab.
- Exec/env: block Python package index override variables from request-scoped host exec environment sanitization so package fetches cannot be redirected through a caller-supplied index. Thanks @nexrin and @vincentkoc.
- Exec/node: stop gateway-side workdir fallback from rewriting explicit `host=node` cwd values to the gateway filesystem, so remote node exec approval and runs keep using the intended node-local directory. (#50961) Thanks @openperf.
- Exec/runtime: default implicit exec to `host=auto`, resolve that target to sandbox only when a sandbox runtime exists, keep explicit `host=sandbox` fail-closed without sandbox, and show `/exec` effective host state in runtime status/docs.
- Exec: fail closed when the implicit sandbox host has no sandbox runtime, and stop denied async approval followups from reusing prior command output from the same session. (#56800) Thanks @scoootscooob.
- Feishu/groups: keep quoted replies and topic bootstrap context aligned with group sender allowlists so only allowlisted thread messages seed agent context. Thanks @AntAISecurityLab and @vincentkoc.
- Gateway/attachments: offload large inbound images without leaking `media://` markers into text-only runs, preserve mixed attachment order for model input/transcripts, and fail closed when model image capability cannot be resolved. (#55513) Thanks @Syysean.
- Gateway/auth: keep shared-auth rate limiting active during WebSocket handshake attempts even when callers also send device-token candidates, so bogus device-token fields no longer suppress shared-secret brute-force tracking. Thanks @kexinoh and @vincentkoc.
- Gateway/auth: reject mismatched browser `Origin` headers on trusted-proxy HTTP operator requests while keeping origin-less headless proxy clients working. Thanks @AntAISecurityLab and @vincentkoc.
- Gateway/device tokens: disconnect active device sessions after token rotation so newly rotated credentials revoke existing live connections immediately instead of waiting for those sockets to close naturally. Thanks @zsxsoft and @vincentkoc.
- Gateway/health: carry webhook-vs-polling account mode from channel descriptors into runtime snapshots so passive channels like LINE and BlueBubbles skip false stale-socket health failures. (#47488) Thanks @karesansui-u.
- Gateway/pairing: restore QR bootstrap onboarding handoff so fresh `/pair qr` iPhone setup can auto-approve the initial node pairing, receive a reusable node device token, and stop retrying with spent bootstrap auth. (#58382) Thanks @ngutman.
- Gateway/OpenAI compatibility: accept flat Responses API function tool definitions on `/v1/responses` and preserve `strict` when normalizing hosted tools into the embedded runner, so spec-compliant clients like Codex no longer fail validation or silently lose strict tool enforcement. Thanks @malaiwah and @vincentkoc.
- Gateway/OpenAI HTTP: restore default operator scopes for bearer-authenticated requests that omit `x-openclaw-scopes`, so headless `/v1/chat/completions` and session-history callers work again after the recent method-scope hardening. (#57596) Thanks @openperf.
- Gateway/plugins: scope plugin-auth HTTP route runtime clients to read-only access and keep gateway-authenticated plugin routes on write scope, so plugin-owned webhook handlers do not inherit write-capable runtime access by default. Thanks @davidluzsilva and @vincentkoc.
- Gateway/SecretRef: resolve restart token drift checks with merged service/runtime env sources and hard-fail unsupported mutable SecretRef plus OAuth-profile combinations so restart warnings and policy enforcement match runtime behavior. (#58141) Thanks @joshavant.
- Gateway/tools HTTP: tighten HTTP tool-invoke authorization so owner-only tools stay off HTTP invoke paths. (#57773) Thanks @jacobtomlinson.
- Harden async approval followup delivery in webchat-only sessions (#57359) Thanks @joshavant.
- Heartbeat/auth: prevent exec-event heartbeat runs from inheriting owner-only tool access from the session delivery target, so node exec output stays on the non-owner tool surface even when the target session belongs to the owner. Thanks @AntAISecurityLab and @vincentkoc.
- Hooks/config: accept runtime channel plugin ids in `hooks.mappings[].channel` (for example `feishu`) instead of rejecting non-core channels during config validation. (#56226) Thanks @AiKrai001.
- Hooks/session routing: rebind hook-triggered `agent:` session keys to the actual target agent before isolated dispatch so dedicated hook agents keep their own session-scoped tool and plugin identity. Thanks @kexinoh and @vincentkoc.
- Host exec/env: block additional request-scoped env overrides that can redirect Docker endpoints, trust roots, compiler include paths, package resolution, or Python environment roots during approved host runs. Thanks @tdjackey and @vincentkoc.
- Image generation/build: write stable runtime alias files into `dist/` and route provider-auth runtime lookups through those aliases so image-generation providers keep resolving auth/runtime modules after rebuilds instead of crashing on missing hashed chunk files.
- iOS/Live Activities: mark the `ActivityKit` import in `LiveActivityManager.swift` as `@preconcurrency` so Xcode 26.4 / Swift 6 builds stop failing on strict concurrency checks. (#57180) Thanks @ngutman.
- LINE/ACP: add current-conversation binding and inbound binding-routing parity so `/acp spawn ... --thread here`, configured ACP bindings, and active conversation-bound ACP sessions work on LINE like the other conversation channels.
- LINE/markdown: preserve underscores inside Latin, Cyrillic, and CJK words when stripping markdown, while still removing standalone `_italic_` markers on the shared text-runtime path used by LINE and TTS. (#47465) Thanks @jackjin1997.
- Agents/failover: make overloaded same-provider retry count and retry delay configurable via `auth.cooldowns`, default to one retry with no delay, and document the model-fallback behavior.
<!-- OPENCLAW_VERSION_END -->

---

## 이미지 사양

| 항목 | 내용 |
|---|---|
| 베이스 | `nvidia/cuda:12.8.1-runtime-ubuntu22.04` |
| CUDA | 12.8.1 (Pascal ~ Blackwell 전 GPU 지원) |
| 최소 호스트 드라이버 | `>= 570.124.06` |
| OS | Ubuntu 22.04 LTS |
| Node.js | 24 |
| OpenClaw | latest |
| Ollama | latest |

### 사전 설치 도구

`git` `curl` `wget` `nano` `vim` `python3` `pip` `npm` `jq` `build-essential`

---

## 구성

```
컨테이너 내부
├── Ollama (127.0.0.1:11434)       ← 로컬 LLM 추론 서버
└── OpenClaw gateway (127.0.0.1:18789)
        ↕ Telegram Bot API (long-polling)
        Telegram 사용자
```

- API 비용 없음 — 외부 AI API 사용하지 않고 Ollama 로컬 모델만 사용
- gcube 클라우드 저장소는 `/data/data` 경로로 자동 마운트됨

---

## 환경변수

### 필수

| 변수 | 예시 | 설명 |
|---|---|---|
| `TELEGRAM_BOT_TOKEN` | `123456:ABC-DEF...` | [@BotFather](https://t.me/BotFather) 에서 발급 |
| `TELEGRAM_ALLOWED_USER_IDS` | `123456789` 또는 `123456789,987654321` | 봇을 사용할 Telegram 수치형 User ID (쉼표로 여러 명 가능) |
| `OLLAMA_MODEL` | `qwen3:14b` | 사용할 Ollama 모델. **반드시 태그 포함** (예: `:14b`, `:8b`) |

> **OLLAMA_MODEL 주의**: 태그 없이 모델명만 지정하면 `:latest` 로 시도합니다.
> `:latest` 태그가 없는 모델은 다운로드 오류가 발생합니다. 항상 명시적 태그를 사용하세요.
>
> 사용 가능한 태그 확인: https://ollama.com/library

### 선택

GitHub 관련 변수는 모두 선택사항. `GITHUB_USERNAME`과 `GITHUB_EMAIL`이 없으면 GitHub 설정 전체가 스킵됨.

| 변수 | 예시 | 설명 |
|---|---|---|
| `GITHUB_USERNAME` | `your-username` | git config user.name |
| `GITHUB_EMAIL` | `you@example.com` | git config user.email |
| `GITHUB_TOKEN` | `ghp_...` | GitHub Personal Access Token (git push 인증) |
| `GITHUB_REPO_URL` | `https://github.com/you/repo` | 컨테이너 시작 시 `/workspace` 에 클론할 repo URL |

---

## GitHub Personal Access Token 발급 방법

GitHub → Settings → Developer settings → **Personal access tokens** → Tokens (classic) → Generate new token

### 필요 권한 (Scope)

| Scope | 이유 |
|---|---|
| `repo` | private repo 클론(`GITHUB_REPO_URL`) 및 git push(`GITHUB_TOKEN`) |

> public repo만 사용한다면 `repo` 대신 `public_repo` 만 선택해도 됨.

**Fine-grained token** 을 사용하는 경우 (더 세밀한 권한 제어):

| 권한 항목 | 수준 |
|---|---|
| Contents | Read and Write |
| Metadata | Read (자동 포함) |

토큰 생성 후 `GITHUB_TOKEN` 환경변수에 입력. `ghp_` 로 시작하는 문자열.

---

## Telegram User ID 확인 방법

봇을 처음 사용하기 전에 본인의 Telegram 수치형 User ID가 필요합니다.

1. [@userinfobot](https://t.me/userinfobot) 에 `/start` 전송
2. 표시된 `Id:` 숫자를 `TELEGRAM_ALLOWED_USER_IDS` 에 입력

---

## gcube 워크로드 배포

### 사전 준비: 이미지 공개 설정

ghcr.io 패키지는 기본적으로 비공개. gcube에서 접근하려면 공개로 변경 필요.

1. GitHub → [Packages](https://github.com/chaeyoon-08?tab=packages) 에서 `openclaw-ollama-baseimage` 선택
2. Package settings → Change visibility → **Public** 으로 변경

> 비공개로 유지하고 싶다면 gcube Storage Management에서 ghcr.io 인증 정보를 등록해야 함.

---

### 워크로드 등록 단계

**1단계 — 이미지 입력**

```
ghcr.io/chaeyoon-08/openclaw-ollama-baseimage:latest
```

**2단계 — 리소스 설정**

| 항목 | 권장값 |
|---|---|
| GPU | 1개 이상 |
| 최소 CUDA 버전 | `12.8` |
| Shared Memory | `1GB` 이상 |

**3단계 — 환경변수 설정**

| 변수 | 값 |
|---|---|
| `TELEGRAM_BOT_TOKEN` | BotFather에서 발급한 토큰 |
| `TELEGRAM_ALLOWED_USER_IDS` | 본인 Telegram user ID (예: `8374448391`) |
| `OLLAMA_MODEL` | 사용할 모델 (예: `qwen3:14b`) |
| `GITHUB_USERNAME` | (선택) GitHub 사용자명 |
| `GITHUB_EMAIL` | (선택) GitHub 이메일 |
| `GITHUB_TOKEN` | (선택) GitHub Personal Access Token |
| `GITHUB_REPO_URL` | (선택) 클론할 repo URL |

**4단계 — 포트 설정**

| 컨테이너 포트 | 용도 |
|---|---|
| `18789` | OpenClaw Control UI 및 gateway |

gcube 워크로드 등록 시 포트 `18789` 를 Service URL로 노출하도록 설정.

**5단계 — 저장소 연결** (선택)

Storage Management에서 Dropbox 또는 AWS S3 연결 후 워크로드에 마운트.
컨테이너 내부에서 `/data/data` 경로로 접근 가능.

**6단계 — 배포 확인**

배포 후 워크로드 로그에서 아래 메시지 확인:

```
[ DONE ] All services started
  Ollama model  : qwen3:14b
  Gateway token : <자동생성토큰>
```

**Control UI 접근:**
```
http://<gcube-service-url>/__openclaw__/
```
접속 후 로그에 출력된 `Gateway token` 값을 입력하면 OpenClaw 관리 화면으로 진입.

로그 출력 후 Telegram에서 봇에게 메시지 보내면 바로 응답.

---

## workspace 백업/복원

컨테이너가 내려가면 `/root/.openclaw/workspace` 내용이 사라집니다.
`GITHUB_REPO_URL`로 클론된 `/workspace`에 백업하여 git push로 보존할 수 있습니다.

### backup.sh

`/root/.openclaw/workspace` 내용을 `/workspace/.openclaw_copy`로 복사합니다.
컨테이너가 내려가면 `/root/.openclaw/workspace`는 사라지므로, 내려가기 전에 실행하여 `git push`로 보존합니다.

```bash
/workspace/backup.sh
# → /workspace/.openclaw_copy 로 복사 후 git push 명령어 안내
```

### restore.sh

`/workspace/.openclaw_copy` 내용을 `/root/.openclaw/workspace`로 복사합니다.
컨테이너 재시작 후 자동 복원이 안 됐을 때 수동으로 이전 작업 내용을 불러옵니다.

```bash
/workspace/restore.sh
# → 복원 후 openclaw 재시작 명령어 안내
```

### 자동 복원

사전에 `backup.sh` + `git push`가 되어 있는 경우, 컨테이너 재시작 시 git repo를 재클론하면서 `.openclaw_copy`가 함께 내려옵니다. entrypoint.sh가 이를 감지하여 자동으로 복원합니다.

### openclaw gateway 재시작 (컨테이너 유지)

```bash
pkill -f openclaw-gateway
# → 3초 이내 자동 재기동, 컨테이너 종료 없음
```

---

## 로컬 테스트

```bash
# .env 파일 생성
cat > .env << 'EOF'
TELEGRAM_BOT_TOKEN=your_bot_token
TELEGRAM_ALLOWED_USER_IDS=your_telegram_user_id
OLLAMA_MODEL=qwen3:8b
EOF

# NVIDIA GPU 있는 경우
docker compose up

# GPU 없는 경우 (CPU 추론, 속도 느림)
docker run --env-file .env ghcr.io/<owner>/openclaw-base:latest
```

### 직접 빌드

```bash
docker build -t openclaw-base .
docker run --gpus all --env-file .env openclaw-base
```

---

## GitHub Actions 자동 빌드

`main` 브랜치에 push 하거나 `v*.*.*` 태그를 달면 자동으로 이미지를 빌드하여 ghcr.io 에 push 합니다.

**생성되는 이미지 태그:**
- `main` push → `:main`, `:latest`, `:sha-<7자>`
- `v1.2.3` 태그 → `:1.2.3`, `:1.2`, `:1`, `:latest`, `:sha-<7자>`
- 수동 실행 (`workflow_dispatch`) → 선택한 브랜치 기준

별도 시크릿 설정 불필요 — `GITHUB_TOKEN` 으로 ghcr.io 인증.

---

## 참고

- OpenClaw 문서: https://docs.openclaw.ai
- Ollama 모델 목록: https://ollama.com/library
- gcube 플랫폼 문서: https://data-alliance.github.io/gai-platform-docs/
