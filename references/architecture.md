# VORTEX-OS — Architecture

> **Status:** Living document. Update when the architecture changes (any of ADR-001 through ADR-015).
> **Audience:** Anyone wanting a visual map of how VORTEX-OS fits together.
> **Scope:** Both [`vortex-os-dotnet`](https://github.com/Cloudmeru/vortex-os-dotnet) (the .NET 10 C++/CLI engine) and [`vortex-os-skill`](https://github.com/Cloudmeru/vortex-os-skill) (the PowerShell skill package).

This document is the **visual companion** to `idea-architecture-decisions.md`. Where the ADRs explain the *why* behind each design choice in prose, this file shows the *what* as diagrams.

---

## The big picture

```mermaid
flowchart TB
    User(["👤 User<br/>(natural-language request)"])
    Agent(["🤖 Code Agent<br/>(minimax code / hermes / etc.)"])
    Skill(["📦 VORTEX-OS Skill<br/>(PowerShell package)"])
    Engine(["⚙️ Vortex.dll<br/>(.NET 10 C++/CLI engine)"])
    LLM(["🧠 LLM<br/>(writer / coder / researcher / analyst / data / media)"])
    State[("📁 VORTEX_HOME<br/>%APPDATA%\\Vortex-OS\\")]
    GitHub(["🌐 GitHub<br/>(vortex-os-dotnet releases)"])

    User -->|"natural language<br/>prompt"| Agent
    Agent -->|"reads SKILL.md,<br/>runs skill.ps1"| Skill
    Skill -->|"auto-update.ps1<br/>(once per 6h)"| GitHub
    GitHub -->|"Vortex.dll + .psm1 + .psd1 + ijwhost.dll"| Skill
    Skill -->|"Add-Type Vortex.dll"| Engine
    Engine -->|"dispatch to"| LLM
    LLM -->|"output (prose, code, research, data, media)"| Engine
    Engine -->|"writes audit + deliverables"| State
    Engine -->|"HITL gate"| Agent
    Agent -->|"Approve / Deny"| Engine

    classDef user fill:#f9e79f,stroke:#b7950b,color:#000
    classDef agent fill:#aed6f1,stroke:#2874a6,color:#000
    classDef skill fill:#d5f5e3,stroke:#1e8449,color:#000
    classDef engine fill:#fadbd8,stroke:#922b21,color:#000
    classDef llm fill:#e8daef,stroke:#6c3483,color:#000
    classDef state fill:#fcf3cf,stroke:#7d6608,color:#000
    classDef github fill:#d6dbdf,stroke:#283747,color:#000

    class User user
    class Agent agent
    class Skill skill
    class Engine engine
    class LLM llm
    class State state
    class GitHub github
```

Read it left to right: the user types a request, the code agent reads the skill and invokes it, the skill installs the engine from GitHub, the engine dispatches to LLMs, results go to durable state, and HITL gates are surfaced back to the user.

---

## The 4-tier agent chain

This is the core orchestration pattern. The engine decomposes a master objective into 4 layers:

```mermaid
flowchart TB
    Obj(["📋 master objective<br/>(e.g. release_v2/objective.md)"])
    T0(["**T0** General Manager<br/><i>parse_objective</i>"])
    T1(["**T1** Store Supervisor<br/><i>macro_plan</i>"])
    T2(["**T2** Shift Supervisor<br/><i>decompose_to_workers</i>"])
    T2b(["**T2** Inspector Governance<br/><i>continuity_check</i>"])
    T2c(["**T2** Self-Healing Optimizer<br/><i>prompt_rewrite</i>"])
    T3w(["**T3** worker.writer"])
    T3a(["**T3** worker.audio"])
    T3i(["**T3** worker.image"])
    T3c(["**T3** worker.code"])
    T3d(["**T3** worker.data"])
    T3r(["**T3** worker.researcher"])
    T3p(["**T3** worker.packager<br/><i>(new in v0.1.9)</i>"])
    Del(("📁 deliverables/<br/>&lt;project&gt;/"))

    Obj --> T0
    T0 --> T1
    T1 --> T2
    T2 --> T3w
    T2 --> T3a
    T2 --> T3i
    T2 --> T3c
    T2 --> T3d
    T2 --> T3r
    T3w -.continuity violation.-> T2b
    T2b -.REJECT.-> T2c
    T2c -.hardened prompt.-> T3w
    T3w --> T2b
    T2b --> T3p
    T3a --> T3p
    T3i --> T3p
    T3c --> T3p
    T3d --> T3p
    T3r --> T3p
    T3p --> Del

    classDef tier0 fill:#fadbd8,stroke:#922b21,color:#000
    classDef tier1 fill:#f9e79f,stroke:#b7950b,color:#000
    classDef tier2 fill:#aed6f1,stroke:#2874a6,color:#000
    classDef tier3 fill:#d5f5e3,stroke:#1e8449,color:#000
    classDef out fill:#fcf3cf,stroke:#7d6608,color:#000

    class T0 tier0
    class T1 tier1
    class T2,T2b,T2c tier2
    class T3w,T3a,T3i,T3c,T3d,T3r,T3p tier3
    class Del,Obj out
```

Read top-to-bottom:
- **T0** parses the master objective into a macro plan
- **T1** (Store Supervisor) decomposes into per-domain tasks
- **T2** (Shift Supervisor) dispatches to T3 workers in parallel
- **T2b** (Inspector) checks every worker output against the continuity rules; rejects on violation
- **T2c** (Self-Healing Optimizer) rewrites the offending prompt with explicit constraints
- **T3 workers** (writer / audio / image / code / data / researcher / packager) generate the deliverables
- **T3 packager** promotes the swarm's intermediate deliverables to the durable `deliverables/<project>/` location (new in v0.1.9)

The self-heal loop (T3w → T2b → T2c → T3w) is what makes the engine "recover from LLM drift" without human intervention. See `references/INSTRUCTIONS.md` §4 for the operator-facing walkthrough.

---

## The storage split (SkillDir vs HomeDir)

This is the most architecturally important diagram in the project. **Read it before touching any storage code.**

```mermaid
flowchart LR
    subgraph SF["📂 Skill Folder (mutable, replaced on update)"]
        SF1["skill.ps1"]
        SF2["verify.ps1"]
        SF3["install.ps1 / install-deps.ps1"]
        SF4["auto-update.ps1 / migrate-state.ps1 / uninstall.ps1"]
        SF5["SKILL.md / README.md / references/INSTRUCTIONS.md"]
        SF6["_meta.json / CHANGELOG.md / idea-*.md"]
        SF7["agents/<supervisor.store>.json<br/>agents/<supervisor.shift>.json<br/>agents/<inspector.governance>.json"]
        SF8["templates/iteration_pattern*.json<br/>(Golden Path, new in v0.1.9)"]
    end

    subgraph VH["📁 VORTEX_HOME (durable, survives skill updates)"]
        VH1["state/<br/>pending_approvals/<br/>auto-update-check.json<br/>decision_history.json<br/>inspector_interventions.log"]
        VH2["memory/<br/>audit.jsonl"]
        VH3["swarms/<br/>active_<id>/<br/>completed_<id>/"]
        VH4["deliverables/<br/>&lt;project&gt;/<br/>  ├── research_notes.md<br/>  ├── data_pipeline.py<br/>  ├── summary.pdf<br/>  └── .manifest.json"]
        VH5["tasks/"]
        VH6["deliverables/_unfiled/<br/>(legacy data from -AdoptFlat)"]
    end

    SF1 -. "reads agents/ on each dispatch" .-> SF7
    SF1 -. "reads $env:VORTEX_HOME" .-> VH
    SF1 -. "writes deliverables/&lt;project&gt;/ on HITL approve" .-> VH4
    SF3 -. "downloads Vortex.dll from GitHub" .-> SF1
    SF3 -. "places in $HOME\\Documents\\PowerShell\\Modules\\Vortex\\&lt;version&gt;\\" .-> SF1
    SF4 -. "queries GitHub, writes state/auto-update-check.json" .-> VH1
    SF4 -. "calls install.ps1 if newer version available" .-> SF3
    SF8 -. "Golden Path templates are stored here<br/>(user data, not skill data)" .-> VH

    classDef skilldir fill:#d5f5e3,stroke:#1e8449,color:#000
    classDef homedir fill:#fcf3cf,stroke:#7d6608,color:#000

    class SF1,SF2,SF3,SF4,SF5,SF6,SF7,SF8 skilldir
    class VH1,VH2,VH3,VH4,VH5,VH6 homedir
```

**The two golden rules:**

1. **Anything in the Skill Folder can be replaced at any time** by `git pull` or a fresh deploy. The user should never have irreplaceable data there.
2. **Anything in VORTEX_HOME is durable and shared** across skill instances on the same machine. The engine + skill always read/write there.

If you're writing code that needs to know where data lives, default to VORTEX_HOME unless it's a script / agent manifest / template (which are Skill Folder).

---

## The install flow (first-run)

What happens when a user runs `pwsh -File skill.ps1 --agents-discover` on a fresh machine:

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant S as skill.ps1
    participant A as auto-update.ps1
    participant G as GitHub
    participant I as install.ps1
    participant E as Vortex.dll
    participant M as PSModulePath

    U->>S: pwsh -File skill.ps1 --agents-discover
    S->>S: set $env:VORTEX_SKILL_ROOT
    S->>A: invoke (rate-limited to once per 6h)
    A->>G: GET /repos/.../releases/latest
    G-->>A: v0.1.9 (latest)
    A->>I: invoke install.ps1 if newer
    I->>G: GET /releases/download/v0.1.9/{Vortex.dll, Vortex.psm1, Vortex.psd1, ijwhost.dll}
    G-->>I: 4 files
    I->>M: place in Vortex\0.1.9\
    M-->>S: Import-Module Vortex finds 0.1.9
    S->>E: Add-Type Vortex.dll
    E-->>S: types loaded
    S->>U: agents-discover output
```

Read it top-to-bottom: the user invokes `skill.ps1` once. The skill does the GitHub check (cached for 6h), downloads the engine if needed, loads it via `Add-Type`, and dispatches the command. Subsequent invocations skip the GitHub call (rate limit) and the download (engine is already installed).

---

## The dispatch + HITL flow (the heart of the skill)

This is what happens when the user runs `skill.ps1 --dispatch-master objective.md`:

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant A as Code Agent
    participant S as skill.ps1
    participant V as Vortex.dll
    participant W as T3 Workers (writer, audio, image, code)
    participant C as Continuity Engine
    participant SH as Self-Healing Optimizer
    participant H as HITL Gate
    participant D as $VORTEX_HOME/deliverables/

    U->>A: "Build me a release readiness report for..."
    A->>S: pwsh -File skill.ps1 -Project foo --dispatch-master obj.md
    S->>V: Vortex.Skill::Run(skillRoot, args)
    V->>V: ResolveProjectName → "foo"
    V->>V: PathResolver::Resolve(skillDir, homeDir, "foo")
    V->>W: spawn N T3 workers in parallel
    W->>C: check output against continuity rules
    alt violation
        C-->>SH: REJECT (e.g. "dashboard drifted from the brand palette")
        SH->>W: re-dispatch with hardened prompt
        W->>C: check again
    end
    C-->>H: PENDING_HUMAN (gate 1: artifact draft approval)
    H->>A: surface gate to agent
    A->>U: "VORTEX-OS wants approval for the draft. Approve?"
    U-->>A: "Approve"
    A->>S: pwsh -File skill.ps1 --hitl-approve <task_id>
    S->>V: Vortex.Skill::Run(... --hitl-approve <task_id>)
    V->>D: copy swarms/active_<id>/deliverables/* to deliverables/foo/
    D-->>V: N files written
    V->>V: write deliverables/foo/.manifest.json
    V-->>H: PENDING_HUMAN (gate 2: final pack approval)
    H->>A: surface gate to agent
    A->>U: "All N deliverables ready. Approve final pack?"
    U-->>A: "Approve"
    V->>D: deliverables/foo/ complete + .manifest.json updated
    D-->>U: open deliverables/foo/ in file explorer
```

Read it top-to-bottom: the user types a request, the agent dispatches, the engine runs the 4-tier chain, the Continuity Engine catches violations, the Self-Healing Optimizer rewrites the prompt, the operator gets HITL gates at script approval and final pack approval. The packager (new in v0.1.9) writes the deliverables to the durable location.

---

## The auto-update flow (silent, every 6h)

```mermaid
sequenceDiagram
    autonumber
    participant S as skill.ps1
    participant A as auto-update.ps1
    participant C as state/auto-update-check.json
    participant G as GitHub
    participant I as install.ps1

    S->>A: invoke on every skill.ps1 run
    A->>C: read last_check
    alt recent (within 6h)
        C-->>A: 4 min ago
        A-->>S: skip (silently)
    else stale (> 6h ago or missing)
        A->>G: GET /repos/.../releases/latest
        G-->>A: tag_name
        A->>A: compare with installed
        alt newer version available
            A->>I: invoke install.ps1
            I->>G: download 4 files
            I-->>A: installed to Vortex\<new_version>\
        end
        A->>C: write new last_check + remote_tag + updated
    end
```

This runs silently. The user sees a one-line message only when an update is found. The 6h cache means at most 4 GitHub calls per day per `VORTEX_HOME`.

---

## The data lifecycle (one project's journey)

What happens to a single project's data from first dispatch to permanent archive:

```mermaid
stateDiagram-v2
    [*] --> UserDrafts: user writes objective.md
    UserDrafts --> SwarmSpawned: skill.ps1 --dispatch-master
    SwarmSpawned --> WorkersRunning: T3 workers generate
    WorkersRunning --> ContinuityCheck: Inspector Governance
    ContinuityCheck --> SelfHeal: violation detected
    SelfHeal --> WorkersRunning: hardened prompt re-dispatch
    WorkersRunning --> HITLScript: artifact gate (HIGH)
    HITLScript --> WorkersRunning: user approves
    WorkersRunning --> HITLPack: final pack gate (HIGH)
    HITLPack --> Promoted: user approves
    Promoted --> DurableState: deliverables/<project>/*.*
    DurableState --> [*]: next project / next iteration

    note right of DurableState
        Files here survive
        skill updates forever
        (lives in $VORTEX_HOME,
        not the skill folder)
    end note
```

Read it: the user's project goes through 4 states (draft → swarm → HITL → durable) and ends in `deliverables/<project>/` which lives forever in VORTEX_HOME.

---

## Component reference

If you want to know which file holds which piece of the architecture, this is the canonical map:

```mermaid
flowchart TB
    subgraph "vortex-os-skill repo"
        SK["SKILL.md<br/>(lean entry, ~10 KB)"]
        REF["references/INSTRUCTIONS.md<br/>(operator playbook, ~20 KB)"]
        ARCH["references/architecture.md<br/>(this file)"]
        SP["skill.ps1<br/>(self-bootstrapping CLI)"]
        VP["verify.ps1<br/>(post-upload verification)"]
        IP["install.ps1<br/>(engine installer)"]
        IDP["install-deps.ps1<br/>(winget-based deps)"]
        AUP["auto-update.ps1<br/>(GitHub check, 6h cache)"]
        MP["migrate-state.ps1<br/>(legacy data move)"]
        UP["uninstall.ps1<br/>(clean removal)"]
        BP["build.ps1<br/>(source-build helper)"]
        AG["agents/*.json<br/>(3 supervisor/inspector manifests)"]
        TP["templates/iteration_pattern*.json<br/>(Golden Path, v0.1.9+)"]
        MJ["_meta.json<br/>(platform metadata)"]
        CH["CHANGELOG.md"]
        IDR["idea-future-recommendations.md"]
        IDA["idea-architecture-decisions.md"]
        IDF["idea-faq-and-pitfalls.md"]
    end

    subgraph "vortex-os-dotnet repo"
        VH["VortexCommon.h<br/>(Paths struct, PathResolver, Slugify)"]
        SP_["skill.cpp<br/>(Vortex::Skill::Run, Dispatch)"]
        VP_["verify.cpp<br/>(Vortex::Verify::Run)"]
        CMD["lib/Commands.cpp<br/>(agents-discover, lint, etc.)"]
        SWM["lib/Swarm.cpp"]
        BP_["src/build.ps1<br/>(cl.exe / link.exe driver)"]
        PSD["Vortex.psd1<br/>(module manifest)"]
        PSM["Vortex.psm1<br/>(module script)"]
        DL["Vortex.dll<br/>(class library)"]
        IJ["ijwhost.dll<br/>(.NET 10 IJW host)"]
    end

    SK -. "loaded on every trigger" .-> Agent
    SP -- "calls" --> IP
    SP -- "calls" --> AUP
    SP -- "calls" --> V
    V -- "implemented in" --> VH
    V -- "implemented in" --> SP_
    IP -- "downloads from GitHub" --> DL
    IP -- "downloads from GitHub" --> PSD
    IP -- "downloads from GitHub" --> PSM
    IP -- "downloads from GitHub" --> IJ
    AUP -- "checks" --> GitHub
    AUP -- "invokes" --> IP
    VP -- "calls" --> V
    IDP -- "uses" --> WINGET["winget (Windows)"]
    MP -- "moves" --> VORTEX_HOME
    UP -- "removes" --> DL

    SP_ -- "uses Paths from" --> VH
    VP_ -- "uses Paths from" --> VH
    CMD -- "uses Paths from" --> VH
    SWM -- "uses Paths from" --> VH
    BP_ -- "builds" --> DL

    classDef skillfile fill:#d5f5e3,stroke:#1e8449,color:#000
    classDef enginefile fill:#fadbd8,stroke:#922b21,color:#000
    classDef external fill:#d6dbdf,stroke:#283747,color:#000

    class SK,REF,ARCH,SP,VP,IP,IDP,AUP,MP,UP,BP,AG,TP,MJ,CH,IDR,IDA,IDF skillfile
    class VH,SP_,VP_,CMD,SWM,BP_,PSD,PSM,DL,IJ enginefile
    class WINGET,GitHub,Agent external
```

---

## How to use this file

- **Onboarding a new contributor:** show them this file + `idea-architecture-decisions.md`. They get the visual + the *why* in one sitting.
- **Reviewing a PR:** "where does this fit?" → find the relevant diagram, find the relevant ADR.
- **Designing a new feature:** "what's the data flow?" → extend the dispatch sequence diagram. "What state does it touch?" → extend the storage split diagram.
- **Debugging a runtime issue:** "where is X coming from?" → use the component reference to find the file.

---

*Last updated: 2026-08-28. Current versions: `vortex-os-skill` v0.3.1, `vortex-os-dotnet` v0.3.0. New diagrams will be added when ADRs are added — keep them in sync.*
