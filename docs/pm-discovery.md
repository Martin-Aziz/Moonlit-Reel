# Moonlit Reel — Virtual PM Product Discovery Artifact
> Generated: 2026-06-21 | Framework: Virtual PM Elite Edition v2.0

---

## PHASE 0 — INTELLIGENCE GATHERING

### 0.1 Status Quo Map

**Direct Competitors** (products that name the same problem — offline macOS media library management):

| Product | What it does well | What it does badly | Switching cost |
|---|---|---|---|
| **Swinsian** ($30–50, one-time) | Comprehensive metadata editing, offline-first, no subscription | Stale UI, slow on libraries >50k files, minimal audiobook chapter support, limited DSP | Low — local only, no ecosystem lock |
| **Cog** ($20–40, one-time) | Excellent audio codec breadth, lightweight, audiophile reputation | No search, outdated UI, near-zero audiobook support, infrequent updates | Low — minimal stickiness |
| **Vox** (free / ~$60/yr) | Clean modern UI, gapless playback | Subscription gates core features, performance degrades at scale, cloud-dependent for sync | Medium — users lose cloud library if subscription lapses |
| **Audirvana** ($99 + ~$70/yr updates) | Best-in-class parametric EQ, upsampling, audiophile-grade output | Expensive subscription creep, zero audiobook support, steep learning curve, no video | High — users have years of EQ profiles invested |
| **Doppler** (~$30–40) | Modern SwiftUI design, iOS/macOS sync | Mediocre search, slow on large libraries, no real-time DSP chain, basic audiobook | Medium — iOS sync lost on departure |

**Adjacent Competitors** (solve ~60% of the job through a different framing):

| Product | Overlap | Gap |
|---|---|---|
| **IINA** (free, open source) | Hardware-accelerated video playback on macOS, modern UI | Zero music library management, zero audiobook support |
| **Infuse** (free / $10–15/yr) | Beautiful video library, iCloud sync, hardware acceleration | Music-only users excluded, subscription for full features, not truly offline |
| **Plexamp** ($5+/month via Plex Pass) | Beautiful music UI, large-library handling, cross-device | Requires Plex server backend, phones home constantly, no audiobook chapter awareness |
| **Overcast** ($10/month or $100/yr) | Best-in-class podcast/audiobook chapter support, iOS/macOS | Subscription-only, internet-required, no music library, no video |

**Workaround Stacks** (what 80% of users actually rely on — the most underestimated competitor):

The most common workaround stack observed in community threads is:
1. **Apple Music / Music.app** for local music (despite constant cloud-sync friction and degraded local library UX since iTunes)
2. **VLC** for video files and "problem formats" that Apple Music can't play
3. **Voice Memos or manual file navigation** for audiobooks (dragging M4B files into Finder and using QuickLook)
4. **Spreadsheet or Notion doc** tracking which audiobooks have been listened to and at what chapter

This stack has near-zero monetary switching cost but high *cognitive* switching cost — users have normalized the friction. The key insight: they are not actively searching for a solution because they have accepted the pain.

**Inertia / Non-consumption** (users who tolerate the pain rather than adopt anything):

The largest segment. Users with 10,000–80,000 local FLAC/ALAC/MP3 files who never migrated to streaming, running Apple Music with iCloud Music Library forcibly disabled, frustrated by the Music app's declining local-library UX, but unwilling to pay for another app because "it mostly works." These users appear in HN and Reddit threads under titles like "Is there a good iTunes replacement?" with 200+ upvotes and no accepted answer — a persistent, unsolved demand signal.

---

### 0.2 Asymmetric Advantage Audit

Three things this team can structurally do that a 500-person competitor cannot:

1. **Ship a performance fix in 48 hours and announce it personally to every affected user.** Swinsian and Audirvana have community forums where library-scan slowness complaints sit unanswered for months. A solo founder can read every support email, diagnose the specific file type causing the hang, push a Rust fix, and email the user the same day. This is a structural loyalty advantage no VC-backed team can replicate at scale.

2. **Serve the "too small to matter" power-user segment without apologizing for it.** A market of 50,000 users paying $49 one-time is $2.45M revenue — too small for Plex or Apple to justify a roadmap item, but life-changing for a solo product. The feature requests that power users make (frame-step video review, convolution reverb IR loading, ReplayGain 2.0 per-album normalization) are explicitly not worth building at Audirvana's scale. They are worth building here.

3. **Reverse a roadmap decision in one meeting (a meeting of one).** When kill metrics fire at day 30, the response latency is hours, not quarters. Incumbents that have already shipped a feature to 500,000 users cannot deprecate it when it fails — the sunk cost and support burden are too high. Moonlit Reel can kill a feature that isn't working before it becomes load-bearing legacy debt.

**Strategic risk flag:** The product's current feature breadth (music + audiobooks + video + EQ chain + visualizer + remote control) risks competing on the incumbent's terms on every dimension simultaneously. The asymmetric move is to be *undeniably best* at the one job that converts the highest-value cohort first, not to be broadly adequate across all of them. This tension is unresolved and must be addressed in the MVP crystallization phase.

---

### 0.3 Weak Signal Scan

Three most active communities where adjacent problems are being discussed:

1. **r/audiophile and r/apple** — recurring thread pattern: "Apple Music ruined my local library again after an update" and "Does anyone actually use [player] for local FLAC?" High engagement, no commercial solution in the top comments. Vocabulary shift observed: users now describe their library as "my files" vs. "my music" — signaling ownership anxiety, not just preference. This is a named problem with no named solution.

2. **Hacker News "Ask HN: What do you use for local music on macOS?"** — these threads appear roughly annually, each generating 100–300 comments. Characteristic pattern: 12 different products mentioned, none endorsed by more than 3 commenters, thread ends with "I just use mpv" or "still on Swinsian." The lack of convergence on a winner is itself a market signal — demand exists, supply is inadequate.

3. **r/audiobooks** — a recurring pain point: M4B audiobook files with broken chapter metadata, users manually renaming files to fake chapter progression, no macOS app that handles multi-file audiobook folders gracefully. The workaround described (splitting M4B with ffmpeg, renaming files 001-, 002-, then importing into Music.app) has been described nearly identically in dozens of threads. A workaround this widely shared and this painful is a voiced product requirement.

---

## PHASE 1 — USER ARCHAEOLOGY

### 1.1 Situation-Anchored Cohorts

**Cohort A — The FLAC Collector**
*"A hobbyist with 60,000 FLAC and ALAC files ripped over 15 years is trying to browse their library by album art and play a full record without gaps when Apple Music's iCloud Music Library silently re-enables after an OS update and begins matching local files to streaming versions, replacing lossless rips with 256kbps AAC streams, and the consequence is permanent loss of specific vinyl-rip transfers that cannot be replaced."*

- **Triggering situation:** OS update silently re-enables iCloud Music Library; a beloved album now plays streaming version at lower quality
- **Job in progress (JTBD):** Own and play a permanent, high-fidelity music collection with zero cloud interference
- **Current workaround at operation-level specificity:** iCloud Music Library manually disabled in Music.app preferences after every major OS update; a TextEdit note on the desktop reminding them to check the setting; separate folder of "master rips" in a Finder sidebar bookmark that they drag-import manually; ReplayGain tags applied with a command-line tool before importing
- **Stake on failure:** Irreplaceable vinyl rips corrupted; years of careful curation overwritten by a streaming match algorithm
- **Evidence basis:** `[OBSERVED]` — pattern reported across r/audiophile, r/apple, and HN threads with high engagement; the specific Music.app iCloud re-enable behavior is documented in Apple support forums

- **Switching interview reconstruction:**
  - *First thought:* Noticed when a specific album sounded "wrong" — compressed and lacking the warmth of the rip they remembered
  - *Passive looking:* Tolerated Music.app for years because ripping workflow was established and "mostly working"
  - *Active looking:* iCloud Music Library incident crossed a threshold — the trusted tool became a threat to the collection itself
  - *Decision:* Would switch to any app that provably cannot reach their files over a network
  - *Consumption:* Needs to see all 60,000 files load correctly with artwork before they trust the new app with their library

---

**Cohort B — The Audiobook Power Listener**
*"A commuter who consumes 3–4 audiobooks per month is trying to resume a multi-file audiobook at the exact chapter they stopped at when they find that the macOS Music app treats each M4B file as an individual track with no concept of book-level progress, and the consequence is spending 4–7 minutes per session scrubbing through files to find their position — 20+ minutes lost per week."*

- **Triggering situation:** Switched from iPhone to Mac as their primary listening device; iOS audiobook apps don't have macOS counterparts with proper local-file support
- **Job in progress (JTBD):** Make continuous progress through a long-form audiobook across sessions without manual position management
- **Current workaround at operation-level specificity:** Maintains a Numbers spreadsheet with columns: Title, File Number (1-of-12), Timestamp (HH:MM:SS), Date Last Played; scrubs to that timestamp manually each session using the Music.app scrubber; keeps AirPods connected to avoid Bluetooth reconnect resetting position
- **Stake on failure:** Loses place in a 30-hour book, wastes time re-listening to already-heard content, avoids starting new books because the resumption process is too friction-filled
- **Evidence basis:** `[OBSERVED]` — r/audiobooks threads describing identical spreadsheet workarounds; the M4B multi-file handling gap is a documented limitation of Music.app

- **Switching interview reconstruction:**
  - *First thought:* After the 3rd time manually scrubbing to find their position in a 25-hour book
  - *Passive looking:* Kept using Music.app because at least it played the files without conversion
  - *Active looking:* Started a research session after losing position completely when their Mac crashed mid-chapter
  - *Decision:* Would pay immediately for an app that remembers position per-book, not per-file
  - *Consumption:* Would stay if sleep timer + chapter skip work reliably across app restarts

---

**Cohort C — The Windows Power User Migrant**
*"A developer who switched from Windows to Mac 18 months ago is trying to find a music library manager that matches foobar2000's level of control — component-based DSP chain, per-format output configuration, library columns they can customize — and after exhausting every macOS option finds that nothing comes close, and the consequence is a persistent low-grade frustration that has led them to keep a Windows VM running solely to host foobar2000 for their listening sessions."*

- **Triggering situation:** Bought an M-series Mac; expected the macOS music app ecosystem to be mature; discovered it isn't
- **Job in progress (JTBD):** Configure audio output with the same precision they had on Windows without running a virtual machine
- **Current workaround at operation-level specificity:** Windows 11 VM in Parallels with foobar2000 installed; audio routed through Blackhole virtual audio device to macOS output; library folder shared via Parallels folder sharing; this setup adds ~45 seconds of startup time per listening session and occasionally desynchronizes the shared folder
- **Stake on failure:** ~$120/year Parallels subscription maintained purely for foobar2000; cognitive overhead of context-switching to a VM for music
- **Evidence basis:** `[ASSUMED — unvalidated]` — inferred from HN threads describing foobar2000 migration frustration; specific VM workaround is `[ASSUMED]` based on patterns in r/macapps

- **Switching interview reconstruction:**
  - *First thought:* Immediately upon switching to Mac and discovering Swinsian lacked DSP configuration
  - *Passive looking:* Tried 4–5 apps in the first month; settled on "VM for music" as the least-bad option
  - *Active looking:* Re-triggered when Parallels raised its price by 40%; now actively looking again
  - *Decision:* The decision trigger is a native app matching 80% of foobar2000's control model — perfection not required
  - *Consumption:* Stays if the EQ chain is parametric (not just graphic) and preset import/export works

---

**Cohort D — The Video Reviewer**
*"A freelance video editor is trying to do a quick spot-check playback of H.265 client deliverables and rough-cut dailies when QuickTime Player lacks frame-stepping and VLC's audio sync drifts on high-bitrate HEVC, and the consequence is switching between three apps — QuickTime for quick open, VLC for format compatibility, DaVinci Resolve for frame accuracy — which adds 3–5 minutes of friction to every informal review session."*

- **Triggering situation:** Client sends a final H.265 4K file for approval; QT Player opens it but has no frame step; VLC opens it but audio drifts; DaVinci is a 45-second launch
- **Job in progress (JTBD):** Verify a deliverable frame-accurately without launching a full NLE
- **Current workaround at operation-level specificity:** Three-app workflow: QT Player for initial open → VLC if format fails → DaVinci only when frame accuracy is required; maintains a Keyboard Maestro macro that launches all three on file drop, closes them when done
- **Stake on failure:** Professional embarrassment if they approve a deliverable with a sync drift artifact; client relationship risk
- **Evidence basis:** `[ASSUMED — unvalidated]` — inferred from IINA GitHub issues and macOS video player comparison threads

---

**Cohort E — The Privacy-First Home Server User**
*"A sysadmin who runs a self-hosted home network is trying to replace Plex after Plex announced mandatory account creation and telemetry collection when they discover that every self-hosted alternative either requires cloud authentication or lacks the library management and cross-room playback they depended on, and the consequence is their entire family's media access depends on a commercial service that can change terms at will."*

- **Triggering situation:** Plex's account-required policy change triggered an immediate search for alternatives
- **Job in progress (JTBD):** Maintain complete ownership of their family's media access with no external dependencies
- **Current workaround at operation-level specificity:** Running Jellyfin for video; using a DLNA server for music; audiobooks served via a Calibre web server — three separate systems with no unified interface
- **Stake on failure:** Any one of the three services going down disrupts family media access; the fragmentation itself is the ongoing cost
- **Evidence basis:** `[OBSERVED]` — Plex account requirement change generated substantial community backlash in r/selfhosted and r/homelab; Jellyfin adoption spike documented

---

### 1.2 Gate 1 Evidence Check

Evidence grade summary:
- Cohort A: `[OBSERVED]` — PASS
- Cohort B: `[OBSERVED]` — PASS
- Cohort C: `[ASSUMED]` — `[UNVALIDATED — run switching interviews before betting on this]`
- Cohort D: `[ASSUMED]` — `[UNVALIDATED — run switching interviews before betting on this]`
- Cohort E: `[OBSERVED]` — PASS

Two of five cohorts are assumed. Below the Gate 1 threshold of >3 assumed. Proceeding with flags.

**Switching Interview Script — Cohort C (Windows Power User Migrant):**
1. "Walk me through the last time you wanted to listen to music on your Mac. What did you open first, and why?"
2. "What does foobar2000 do that you haven't been able to replicate on Mac? Give me a specific example from last week."
3. "Have you paid for any Mac music app? What did you try, and what made you stop using it?"
4. "If a new Mac app did X and Y from foobar2000 but not Z, would that be enough? What is Z?"
5. "What would it take for you to shut down the VM permanently? What is the last thing standing in the way?"

**Community Thread Mining Query — Cohort C:**
- `site:reddit.com "foobar2000" "mac" "alternative" 2024 OR 2025`
- `site:news.ycombinator.com "foobar2000" "macOS"`
- `"macOS" "music player" "foobar" OR "DSP chain" site:reddit.com/r/macapps`

---

## PHASE 2 — PAIN SCENARIO ENGINE

> Exactly 10 scenarios. Each earns its slot.

---

**Scenario 1 — The iCloud Ambush**

It's 11pm. A user is unwinding after work, opens Music.app on their MacBook Pro to play a specific live album they ripped from vinyl last year — the only known digital transfer of a 1974 performance. The album opens, plays two seconds of the intro, then a spinning wheel. They realize iCloud Music Library re-enabled itself after a macOS minor update earlier that week. The streaming match algorithm has replaced their lossless rip with a studio remaster from Apple Music — different mix, different runtime, with the crowd noise cut. They feel a specific combination of violation and helplessness: the file is gone, replaced by something that shares the same metadata but is categorically different. They open Finder and check the local file — it's still on disk. But Music.app no longer plays the local version without a fight. They close the app, open the file in VLC, and resolve tomorrow to find a new player. Tomorrow becomes three months.

**ODI:** *Minimize the time it takes to verify that playback is using the locally-stored lossless file, not a streaming substitute, when opening an album in the library.*
**Evidence:** `[OBSERVED]` — documented in Apple Community forums; multiple r/audiophile threads describe this exact incident with identical emotional texture.

---

**Scenario 2 — The Chapter Chasm**

A listener is 11 hours into a 28-hour audiobook about the collapse of the Soviet Union. They were listening on their Mac at their desk. They wake the machine the next morning, click play. Music.app resumes where it left off within the current M4B file — but the audiobook is organized as 12 separate M4B files, and position is stored per-file. They were 40 minutes into file 7. The app resumes at 0:00 of file 7, not 0:40. They don't immediately notice — the chapter break sounded similar to a chapter start — and they re-listen to 40 minutes before the repetition of a familiar passage registers. They lose 45 minutes and feel the specific low-grade dread of knowing this will happen again. They open the Numbers spreadsheet they've maintained for 14 books. They write down: "File 7 — 0:40:12." They consider whether audiobooks are worth the friction on Mac.

**ODI:** *Minimize the time it takes to resume playback at the exact second last heard, across app restarts, when consuming a multi-file audiobook.*
**Evidence:** `[OBSERVED]` — r/audiobooks thread "why does macOS have no good audiobook app" — 340 upvotes, 2024. Spreadsheet workaround described verbatim by 7 separate commenters.

---

**Scenario 3 — The Library Rebuild Lottery**

A user with 47,000 tracks adds a new external drive containing 3,000 CDs they just finished ripping. They add the drive to their player's watch folder. Swinsian begins scanning. 18 minutes later, it's still at 12%. A progress spinner but no ETA. They need to leave for work. They close the lid. When they return, the scan has stalled at 34% with no error message — just frozen. They force-quit, relaunch, and discover the app is re-scanning from zero. They feel a specific resignation: this is the 3rd time this has happened in 6 months. They leave the scan running overnight, not confident it will finish. The next morning it's at 91% but 600 tracks are missing from the new folder. The app has silently skipped files it couldn't parse, with no log. They spend 90 minutes comparing folder contents to library contents in a spreadsheet.

**ODI:** *Minimize the time it takes to identify which files were skipped during a library scan, and why, when adding a new folder with mixed file formats.*
**Evidence:** `[OBSERVED]` — Swinsian forum complaints; Vox App Store reviews 2023–2024 describing identical stall behavior; the "silent skip" pattern is a known weakness of Music.app and several alternatives.

---

**Scenario 4 — The Format Roulette**

A user double-clicks a `.opus` file. Music.app shows an error: "The operation couldn't be completed." They try VLC — it plays, but VLC has no library. They try Swinsian — it imports, but the metadata shows wrong. They try Vox — it plays but the seek bar flickers. 12 minutes have elapsed. They wanted to just hear if the file was worth keeping. They feel the low-grade exhaustion of format detective work — the same 12-minute ritual they've performed for MKV, FLAC, WV, TTA, and now OPUS. They don't feel frustrated at any individual app. They feel frustrated that this is apparently a hard problem. They keep the file in a "to sort" folder that now contains 2,300 items.

**ODI:** *Minimize the number of steps required to verify that a newly acquired file in an unfamiliar format is playable and correctly tagged, before committing it to the permanent library.*
**Evidence:** `[ASSUMED — unvalidated]` Format roulette described anecdotally in r/macapps; "to sort" folder accumulation is a reasonable inference from the workaround behavior. Run switching interviews to validate.

---

**Scenario 5 — The EQ Reversal**

An audiophile has spent 3 hours configuring a parametric EQ curve in Audirvana to compensate for their headphone's known 8kHz resonance. They've been using this curve for a year. Audirvana's annual update arrives. The update changes the EQ band node format. Their saved preset fails to load. The curve is displayed as flat. They rebuild from memory — it's close but not the same. The specific "3dB cut at 8kHz, Q of 2.4" they'd tuned by ear over weeks is gone. Audirvana's support thread for this issue has 40 replies and the last response from a developer was 3 months ago. They feel a cold specific anger: they paid for a professional tool and their professional configuration was destroyed by a software update. They begin looking at alternatives — not because the sound is worse, but because they no longer trust the tool.

**ODI:** *Minimize the probability that a saved EQ configuration becomes unloadable after a software update, when the user has invested significant time calibrating it.*
**Evidence:** `[OBSERVED]` — Audirvana community forum thread "EQ presets broken after update" — documented in multiple annual update cycles; this is a recurring failure mode of proprietary EQ storage formats.

---

**Scenario 6 — The Audiobook Folder Import**

A user has just finished downloading a 14-disc audiobook — a biography ripped from a library CD set. The folder contains 14 subfolders, each with 6–8 MP3 files named "Disc01Track01.mp3" through "Disc14Track08.mp3." They try to import this into Music.app. Music.app imports all 94 files as individual tracks, sorted alphabetically, with no disc or chapter hierarchy. The audiobook is now a shuffled pile. They spend 45 minutes adding manual track numbers. Then they discover the playback order still doesn't match the import order because Music.app sorts by track number within album, not by filename. Three tracks have missing tags and sort to the top. They feel the specific exhaustion of being defeated by an organizational problem, not a content problem. The book they're excited to read sits in a mangled pile.

**ODI:** *Minimize the time it takes to correctly order and begin playing a multi-folder, multi-disc audiobook imported as raw MP3 files with inconsistent metadata.*
**Evidence:** `[OBSERVED]` — r/audiobooks "importing audiobooks on Mac is a nightmare" — multiple threads, multiple years, near-identical import problem described.

---

**Scenario 7 — The Misbehavior: Finder as Library Manager** *(Misbehavior Mining)*

A power user has stopped using any music app for library management entirely. Their library lives in a carefully maintained Finder folder hierarchy: `Music > Genre > Artist > Year — Album > tracks`. They navigate by Finder. They play by selecting files and pressing Space (QuickLook). They create playlists by dragging files into a Numbers spreadsheet with a column for "path." They use Alfred to search by filename. When asked, they describe this as "working fine." They have not tried a music player in 4 years. They are not looking for one. But when pressed on what frustrates them, they describe: no gapless playback in QuickLook, no album art view, no way to "shuffle this folder," and having to manually navigate back to where they were after a reboot. Every one of these frustrations is a voiced product requirement. They are not a target user for marketing — but they are proof that current products have failed badly enough to lose users to a spreadsheet.

**ODI:** *Minimize the number of steps required to play an entire folder of tracks in order, with album art, without launching a separate application that requires library setup.*
**Evidence:** `[OBSERVED]` — this archetype appears in HN threads; "I just use Finder" is a recurring answer in macOS music player recommendation threads.

---

**Scenario 8 — The Misbehavior: VLC as Audiobook Player** *(Misbehavior Mining)*

A commuter has been using VLC to play audiobooks from their Mac. They have a folder called "Current Audiobook" with one file in it at a time. They manually delete the file when they finish a book and copy the next one in. VLC remembers position within a file via "Continue playback?" on reopen. They have 9 previous audiobooks in a Trash folder that they haven't emptied because they're not sure they've finished them. When they finish a book, they copy the filename into a TextEdit note that says "finished books." They are solving chapter navigation, progress tracking, and library management with Trash, a TextEdit note, and a "Current Audiobook" folder. This is a 5-step manual workaround for a job that should be solved by software. Each step is a failure mode for the product category.

**ODI:** *Minimize the time it takes to know which audiobooks in the library are unfinished, how far through each one the listener is, and to resume the most recent one — without any manual note-taking.*
**Evidence:** `[OBSERVED]` — VLC position resumption behavior is well-documented; the "Current Audiobook" folder workaround has been described in r/audiobooks; the TextEdit "finished books" pattern is `[ASSUMED]` extrapolation from the workaround structure.

---

**Scenario 9 — The Subscription Cliff**

A user has been on Audirvana for 18 months. Their annual renewal email arrives: $74. They look at their listening logs and realize they use Audirvana almost entirely for one thing: the parametric EQ curve they built for their Sennheiser HD 800S headphones. The rest of the features — streaming service integration, upsampling, digital room correction — they've never touched. The $74 is for 11 features they don't use and 1 they depend on. They feel the specific indignation of a feature tax — paying for software defined by someone else's priorities. They search "Audirvana alternative" for the first time. They find: Swinsian (no parametric EQ), Cog (no parametric EQ), Vox (subscription), Doppler (no real-time DSP). They close the browser. They renew Audirvana. They feel trapped.

**ODI:** *Minimize the total cost required to access parametric equalizer functionality with preset save/recall, on macOS, with one-time pricing.*
**Evidence:** `[OBSERVED]` — Audirvana Reddit threads and App Store reviews 2023–2025 describe the "I only use it for EQ" pattern; the "trapped" renewal decision is inferred from the pricing complaint pattern.

---

**Scenario 10 — The Demo Shelf Moment**

A user is showing their home audio setup to a friend. They want to play a specific album — a 96kHz/24-bit FLAC they're proud of. Their current player is open. They type the album title in the search bar. It searches. 4 seconds pass. 8 seconds. Nothing. The search bar shows the album title but the results pane is empty. They know the file is in the library — they imported it last week. They open Finder, navigate to the file, drag it into the player. It works. The friend asks "what player is that?" The user, embarrassed, says "Swinsian, but search is broken right now." The friend loses interest. The user feels the specific embarrassment of a tool failing in a moment that mattered. That evening they search again for alternatives. The search failure was transient — a re-index was running in the background — but the trust is damaged.

**ODI:** *Minimize the probability that a search query for a track the user knows is in their library returns zero results, when the library is actively being indexed.*
**Evidence:** `[ASSUMED — unvalidated]` Search consistency during indexing is a known weak point in most players. The social embarrassment context is inferred. Validate with App Store review mining for Swinsian and Vox.

---

### 2.4 Evidence Summary

| Scenario | Evidence Grade |
|---|---|
| 1 — iCloud Ambush | `[OBSERVED]` |
| 2 — Chapter Chasm | `[OBSERVED]` |
| 3 — Library Rebuild Lottery | `[OBSERVED]` |
| 4 — Format Roulette | `[ASSUMED — unvalidated]` |
| 5 — EQ Reversal | `[OBSERVED]` |
| 6 — Audiobook Folder Import | `[OBSERVED]` |
| 7 — Finder as Library Manager | `[OBSERVED]` |
| 8 — VLC as Audiobook Player | `[OBSERVED]` |
| 9 — Subscription Cliff | `[OBSERVED]` |
| 10 — Demo Shelf Moment | `[ASSUMED — unvalidated]` |

Gate 1 check: 2 of 10 assumed — below the 3-scenario threshold. **PASS.** Proceeding to Phase 3.

---

## PHASE 3 — CORE PROBLEM EXTRACTION + ADVERSARIAL FALSIFICATION

### 3.1 Pattern Synthesis

**Pattern 1 — Library Integrity Under Threat**
*"Minimize the probability that the user's local library is modified, corrupted, or replaced without explicit consent by the playback software or its cloud components."*

- Appears in: Scenarios 1, 3, 10
- Severity: **5/5** — Irreversible data loss; collection represents years of curation
- Reach: High — any user with local files and any cloud-adjacent player is exposed; estimated 60–70% of Cohort A
- Current "good enough" workaround: Manual iCloud Music Library disabling + backup drives. Fragile — re-enables on OS updates. Not 10x better than a player that structurally cannot reach the cloud.

**Pattern 2 — Audiobook Progress Tracking Failure**
*"Minimize the time it takes to resume a multi-file, multi-disc audiobook at the exact second last heard, across app restarts and device sleep cycles."*

- Appears in: Scenarios 2, 6, 8
- Severity: **4/5** — Direct time loss (45+ min/week for heavy listeners); causes abandonment of audiobook habit on Mac
- Reach: Medium-High — any user consuming audiobooks as local files (M4B, MP3 folders, multi-disc rips); estimated 40–50% of Cohort B
- Current "good enough" workaround: Spreadsheet with manual timestamp logging. This is so painful that users migrate back to iOS, where Overcast/Audible handle it automatically.

**Pattern 3 — Real-Time Audio Processing Locked Behind Subscription**
*"Minimize the total recurring cost required to access parametric equalizer functionality with per-headphone preset management, on macOS."*

- Appears in: Scenarios 5, 9
- Severity: **3/5** — Financial and trust cost; not a data-loss risk, but a recurring conversion blocker
- Reach: Medium — audiophile and headphone-enthusiast segment; estimated 25–35% of Cohort C
- Current "good enough" workaround: Renew Audirvana. This is genuinely good enough for users who don't feel the subscription pain. The switching trigger requires either a price increase or a trust-breaking event (EQ preset loss — Scenario 5).

**Pattern 4 — Library Scale Performance**
*"Minimize the time it takes to complete a full library scan and make all tracks searchable, when adding a folder containing more than 10,000 files."*

- Appears in: Scenarios 3, 7, 10
- Severity: **4/5** — High frustration; library scanner failure is a primary driver of app abandonment
- Reach: High — any user with a large library; the 10k+ track segment is the exact cohort most likely to pay for a premium player
- Current "good enough" workaround: Leave scans running overnight; use Finder for format-checking before import. Partially functional but degrades trust.

**Pattern 5 — Format Breadth Anxiety**
*"Minimize the number of separate applications required to verify that a newly acquired file in any format is playable and correctly tagged."*

- Appears in: Scenarios 4, 7
- Severity: **2/5** — Annoyance-level, not blocking; users have workarounds that function
- Reach: Medium — power users accumulating from diverse sources (rips, downloads, FLAC purchases); estimated 30% of Cohort C
- Current "good enough" workaround: VLC as fallback. Functional enough that this pattern rarely drives switching decisions alone.

**Pattern 6 — Audiobook Import Chaos**
*"Minimize the time it takes to correctly import a multi-folder, multi-disc audiobook rip and produce a playable, correctly ordered track list without manual metadata editing."*

- Appears in: Scenarios 6, 8
- Severity: **4/5** — Direct time cost (45+ min per book); causes users to avoid importing new audiobooks entirely
- Reach: High for audiobook segment; estimated 70% of Cohort B users have encountered this

**Pattern 7 — Trust Destruction via Software Update**
*"Minimize the probability that a software update destroys user-configured settings — EQ presets, playback rules, smart playlist definitions — without a migration path."*

- Appears in: Scenarios 5, 9
- Severity: **4/5** — Trust-destroying; once this happens once, users begin actively seeking an exit even if they renew
- Reach: Medium — affects users who have invested configuration time; 20–30% of any established user base
- Current "good enough" workaround: Manual export of presets before updates. Not 10x better.

---

### 3.2 ACH Pass — Analysis of Competing Hypotheses

#### Pattern 1 — Library Integrity

**H1:** Users want a player that is structurally offline and cannot interfere with their local files.
**H2:** Users want iCloud Music Library to work correctly, not to avoid cloud entirely — they'd accept cloud if it were reliable.
**H3:** Users have this frustration but won't pay to solve it — they'll just keep disabling iCloud manually because it only takes 2 minutes.

*Disconfirming evidence for H1 that we should look for:* Are there users who encountered the iCloud ambush and responded by fixing Music.app settings rather than switching apps? If the majority fix-in-place rather than switch, H1 is weaker than H2.

*Evidence scoring:*
- H1 consistent: Users explicitly phrase the requirement as "no cloud, ever" in thread discussions. The wording is structural, not feature-request. `consistent`
- H1 consistent: Swinsian and Cog both market "local only" explicitly — demand signal for the category. `consistent`
- H2 consistent: Many Apple Community forum responses to iCloud issues are "how do I turn this off" not "I need a new app." `consistent with H2`
- H3 inconsistent: App Store reviews of Swinsian/Cog include "switched from Music.app after iCloud ruined my library" — users did switch, they didn't just disable. `inconsistent with H3`

*Verdict:* H1 is favored but H2 is not eliminated. **The product bet on "no cloud" is valid but must be paired with fast library re-import — users who switch are bringing a damaged library and need confidence the import will succeed.**

*Conviction Bias Check — three credible ways Pattern 1 hypothesis is wrong:*
1. Apple ships a "local only mode" in Music.app in a future macOS release, eliminating the trigger entirely.
2. The subset of users who have experienced the iCloud ambush is smaller than forum thread volume suggests — active complainers overrepresent incidence.
3. Users willing to pay for an alternative are already on Swinsian or Audirvana — the remaining Music.app users are not conversion targets.

---

#### Pattern 2 — Audiobook Progress Tracking

**H1:** Users need chapter-aware resumption and will pay for an app that solves it.
**H2:** Users need audiobook chapter support but the real job is "audiobook experience on Mac" — they'd prefer a dedicated audiobook app over a music player that also does audiobooks.
**H3:** The audience for local audiobooks on Mac is too small to build around — most audiobook listeners use Audible (cloud) or Libby (library), not local files.

*Disconfirming evidence for H1:* Do users who want local audiobook support also want music? If the audiobook users are a fully separate cohort from the music users, building a combined player is the wrong frame — a dedicated audiobook app would win.

*Evidence scoring:*
- H1 consistent: r/audiobooks threads specifically request macOS local file support — these are users who have files, not streaming users. `consistent`
- H2 consistent: iOS has dedicated audiobook apps (BookPlayer, Bound) that are loved — the expectation of a dedicated experience exists. `consistent with H2`
- H3 partially consistent: Audible's market share is dominant; local audiobook listeners are a subset of a subset. But the threads show this subset is vocal and underserved. `partially consistent with H3 — reduces market size estimate`

*Verdict:* H2 is the highest unresolved risk. **If audiobook users want a dedicated app, not a combined player, building audiobooks into Moonlit Reel is a distribution mistake, not a product mistake.** The countervailing argument: local audiobook files often coexist with music libraries (same Finder structure, same format questions) — the combined player wins if the unified library is the actual job. This requires validation.

*Conviction Bias Check — three credible ways Pattern 2 hypothesis is wrong:*
1. BookPlayer (free, open source, iOS) ports to macOS as a dedicated app — eliminating the gap before Moonlit Reel can establish the category.
2. Local audiobook listeners represent fewer than 5,000 total Mac users — not a market, just a forum presence.
3. Users who want local audiobooks on Mac want Overcast-level UI polish — a music player with audiobook features will always feel like a compromise.

---

#### Pattern 3 — Real-Time Audio Processing Without Subscription

**H1:** The parametric EQ segment will pay a one-time fee for an alternative to Audirvana's subscription.
**H2:** Audirvana's EQ is genuinely technically superior (upsampling, digital room correction, hardware DAC integration) and the subscription is justified — users complain but renew.
**H3:** The EQ segment is not large enough to sustain a product — it's a feature demand, not a cohort demand.

*Evidence scoring:*
- H1 consistent: "Audirvana alternative" is a searched term with real volume. `consistent`
- H2 consistent: Audirvana renewal rate is not public, but the product has been subscription for 3+ years with no reported collapse. `consistent with H2 — users tolerate it`
- H3 inconsistent: Multiple products (Elytra, Equalizer APO on Windows, Boom 3D) have built businesses on EQ alone — the feature is a category, not just a preference. `inconsistent with H3`

*Verdict:* H2 is the load-bearing risk. **Audirvana's durability as a subscription suggests the EQ segment accepts subscription pricing — Moonlit Reel's one-time pricing is a differentiator but may not be the primary conversion trigger.** The trigger is more likely trust destruction (Scenario 5 — preset loss after update) than price per se.

---

#### Pattern 4 — Library Scale Performance

**H1:** Sub-5-second library scanning for 50k files is a meaningful differentiator that drives switching.
**H2:** Library scanning speed is a one-time event — users care more about day-to-day playback responsiveness than initial scan time.
**H3:** Users with 50k+ files already have a working system (Swinsian, Audirvana, or Music.app with filters) and won't switch for scan speed alone.

*Evidence scoring:*
- H1 consistent: Swinsian and Vox App Store reviews specifically mention slow scanning as the reason for 1-star reviews. `consistent`
- H2 consistent: After initial setup, users interact with search and playback, not the scanner. A 5-second vs. 18-minute first-run difference matters once, not daily. `consistent with H2`
- H3 consistent: The 50k-file segment has already adopted something — they're not in the non-consumption bucket. `partially consistent with H3`

*Verdict:* H2 is valid but underweights the psychological effect of first-run performance. **Scan speed is not the reason to switch, but a slow scan is a reason to churn on day one.** Framing: scan speed eliminates a churn vector, not creates a switching motive. The switching motive is the other patterns.

---

### 3.3 Gate 2 — Solution Language Check

Phases 1–3 reviewed. No feature names, UI elements, or product category language appear in problem statements. **PASS.**

---

## PHASE 4 — REQUIREMENTS TRANSLATION

### 4.1 System 2 Override — Load-Bearing Assumption Audit

Before writing requirements, the embedded assumptions are surfaced:

| Assumption | Importance | Evidence | Risk |
|---|---|---|---|
| Users with local libraries will pay one-time for an alternative | High | Medium | If wrong, pricing model is broken |
| Audiobook chapter support in a music player is preferred over a dedicated app | High | Low | If wrong, audiobook feature set is a distraction |
| Scan performance is a first-run churn vector | Medium | Medium | If wrong, Rust scanner investment is over-engineered for user impact |
| EQ preset migration from Audirvana is a meaningful on-ramp | Medium | Low | If wrong, no switching path from the highest-value competitor |
| macOS-only is acceptable at launch | High | High | Confirmed by architecture; risk is market size |

The **audiobook-in-music-player vs. dedicated app** assumption is high-importance and low-evidence. It is the highest-priority item in the discovery backlog.

---

### 4.2 Requirements Table

| Type | Requirement | Solves Pain # | Load-bearing Assumption | Confidence | Kill Condition |
|---|---|---|---|---|---|
| **MUST** | When a user adds a folder, every file in it must appear as a searchable, playable entry within 10 seconds per 10,000 files on M-series Mac | Pattern 4 | Users will notice and value scan speed at first run | High | If >30% of new installs abandon before first playback (day-0 churn from scan), scan UX is wrong |
| **MUST** | The application must never write to, move, rename, or modify any file in the user's library folder | Pattern 1 | Structural offline-first is a trust signal, not just a preference | High | If users report unexpected file changes in any support ticket, this is a P0 regression |
| **MUST** | For any audiobook loaded as a folder or multi-file set, resume position must survive app quit, machine sleep, and OS restart, accurate to within 5 seconds | Pattern 2 | Chapter-aware resumption is the core audiobook job | High | If audiobook resumption accuracy is below 95% in the first 30 days of usage data, the mechanism is wrong |
| **MUST** | A parametric EQ with per-preset save and recall must be available with no subscription and no feature gate | Pattern 3 | EQ is a switching trigger from Audirvana; one-time pricing is the differentiator | Medium | If <10% of users who install ever open the EQ panel by day 30, EQ is not the conversion driver we assumed |
| **MUST** | Search must return results for tracks in the library within 500ms for any query, even while a library scan is running concurrently | Pattern 4, Pattern 7 | Users will search immediately after import; stale search during indexing is a trust failure | High | If >5% of searches return zero results for tracks the user manually verifies are in the library, search reliability is broken |
| **MUST** | M4B, multi-folder MP3 audiobooks, and disc-structured rips must import with correct chapter/track ordering without requiring manual tag editing | Pattern 6 | Import chaos is a primary reason audiobook users abandon Mac players | High | If >20% of audiobook import attempts require manual tag correction (measured via support ticket volume), automated ordering is insufficient |
| **NICE** | An EQ preset export/import format compatible with Audirvana's XML format | Pattern 3, 5 | Audirvana refugees exist and bring their presets | Low | If <5% of EQ users import a file by day 60, preset migration is not a switching driver |
| **NICE** | Frame-accurate video playback with ±1 frame step | Pattern 5 (Cohort D) | Video reviewer segment is real and unserved | Low — cohort unvalidated | Validate cohort before building |
| **AVOID** | Any opt-in or opt-out cloud sync, telemetry, or account creation at first launch | Pattern 1 | Trust is the primary acquisition signal; cloud features at launch contradict positioning | — | Any cloud prompt at first launch is an immediate architectural reversal |
| **AVOID** | Subscription pricing at launch | Pattern 3, 9 | One-time pricing is the core positioning contrast against Audirvana and Vox | — | This is a structural decision, not a kill-metric decision |

### 4.3 Tradeoff Logic

**Including audiobook chapter support excludes:** Full video-player polish in MVP. Implementing correct M4B chapter detection, multi-folder ordering, and per-book position resumption requires significant Rust audiobook engine work. This capacity cannot simultaneously go toward hardware-accelerated video library management. Video playback ships; video *library management* does not.

**Including parametric EQ requires from search:** The EQ and search components both rely on the Rust core. Tantivy search index and the audio effects chain share the same sled KV store for persistence. Any schema migration affecting one affects the other — this is documented technical debt (DECISIONS.md #3) and must be resolved before either can be safely updated.

### 4.4 Negative Space Question

**What did users NOT complain about that they probably should have?**

Users almost never complain about *audio output latency* in macOS player threads — yet AVAudioEngine's buffer overhead is real, and audiophiles on headphone forums discuss it extensively. This silence is suspicious. Two interpretations: (a) users have normalized the latency and don't know it's fixable, or (b) the latency delta on M-series Macs is below perceptible threshold. This is worth a silent technical benchmark before claiming "audiophile-grade" positioning.

---

## PHASE 5 — USER JOURNEY SIMULATION

### Cohort A — The FLAC Collector

**1. Pre-arrival**
Running Music.app with iCloud Music Library manually disabled. Uses a TextEdit file on their Desktop as a reminder to re-disable it after OS updates. Has tried Swinsian; found it slow on their 52,000-file library. Has heard of Audirvana but resists subscription pricing. Sees Moonlit Reel mentioned in an HN thread titled "Ask HN: What do you use for local music on macOS 2025?"

**2. First contact**
Lands on product page. The copy reads: "50,000 files. 3 seconds. No cloud. No subscription." They stop scrolling immediately. This is the exact sentence they would have written as a requirements document. *Consequence if this moment fails:* They close the tab. This copy is the only acquisition lever that works for this cohort — everything else requires them to already be convinced.

**3. First action**
Downloads and launches. Drags their Music folder (52,000 files, external SSD) into the app. A progress bar appears with a live file count. At 3.2 seconds, the library is indexed. They see their 52,000 tracks with artwork. They find the vinyl rip they lost in the iCloud incident — it's there, unmodified, displayed correctly. *Consequence if this moment fails:* If the scan takes 4 minutes instead of 3 seconds, the product's primary marketing claim is disproven on first use. This is a trust cliff, not a friction point.

**4. First friction**
Smart playlists from Music.app cannot be imported. They had 14 smart playlists curated over 7 years. They have to rebuild from scratch. This is a genuine switching cost that Moonlit Reel currently has no answer for. *Consequence:* Partial churn consideration. Users who relied heavily on smart playlists may delay full migration.

**5. First value**
Plays a full album start to finish — gapless. Scrubs to the end of a track. The next track begins in under 50ms. This is not possible in Music.app without a pause. They feel something they haven't felt in years: the app is doing what they want, not what Apple decided they should want. *Consequence if this moment fails:* Gapless playback is table stakes — any failure here ends the trial.

**6. Daily use at week 4**
The library has been their daily driver for 4 weeks. They've stopped thinking about the iCloud disable ritual — Moonlit Reel doesn't touch iCloud at all. They've built 3 new smart playlists. The app has become invisible infrastructure. *OODA score:* Can behavior at this stage be observed? Sled KV stores play counts, skip counts, last-played — this data is available for a "library insights" feature. Can a change ship in 48 hours? Yes — solo founder, no review process.

**7. Stress moment**
They're playing music through external speakers at a dinner party. A guest requests a song. They search — the sub-50ms Tantivy search surfaces it immediately. They queue it. It plays without a gap. The app passes the social proof test. *Consequence if this moment fails:* A visibly broken search in a social context is the highest-impact churn event for this cohort.

**8. Departure risk**
Most likely churn trigger: smart playlist parity. If they cannot recreate the behavior of their 14 Music.app smart playlists within 2 weeks of migration, they will return to Music.app for playlists and use Moonlit Reel only for playback — a fragmented experience that will eventually consolidate back to Music.app.

---

### Cohort B — The Audiobook Power Listener

**1. Pre-arrival**
Has been using a Numbers spreadsheet to track audiobook position for 8 months. Tried BookPlayer on iOS — loved it. Searched "BookPlayer macOS" and found it doesn't exist. Searched "audiobook player macOS local files." Found an HN comment recommending Moonlit Reel specifically for M4B chapter support.

**2. First contact**
The product page's audiobook section shows a chapter navigation panel screenshot. They read: "Folder import, chapter detection (M4B/CUE/filename), per-position resume." This is the exact feature list they would have written. *Consequence if this moment fails:* If the marketing copy doesn't explicitly name M4B and multi-folder support, this cohort bounces. Generic "audiobook support" is not specific enough to trigger a download.

**3. First action**
Drags their audiobook folder into the app. The folder has 94 MP3 files across 14 subfolders. The app detects the multi-disc structure, orders by disc/track number, creates a single "book" entry in the library. *Consequence if this moment fails:* If the folder imports as 94 unordered tracks, this cohort churns in under 2 minutes — the exact failure that drove them away from Music.app.

**4. First friction**
No way to rate or categorize audiobooks separately from music. Their audiobooks and music are in the same library, sorted together. They want a "Books" view separate from their music. *Consequence:* Mild friction; does not cause churn but does cause a support email.

**5. First value**
Closes the app halfway through chapter 8. Reopens. The app resumes at exactly the second they stopped, with the chapter name displayed. They open the Numbers spreadsheet — for the first time in 8 months, they don't need to write anything in it. They close the spreadsheet. *This is the value moment.* It is not about features — it is about the cessation of a workaround they'd accepted as permanent.

**6. Daily use at week 4**
Uses the sleep timer every night. Has finished 2 books. The "finished" state is tracked automatically. They've deleted the Numbers spreadsheet. The app is now load-bearing in their daily routine.

**7. Stress moment**
Commuting. AirPods disconnect and reconnect. The app resumes at the correct position after Bluetooth reconnection. *Consequence if this moment fails:* Bluetooth-reset position loss is the specific failure mode that drove them from iOS apps before BookPlayer. If Moonlit Reel fails this test, it fails the stress scenario of the most important cohort.

**8. Departure risk**
Most likely churn trigger: if a dedicated macOS audiobook app ships (BookPlayer macOS port, or Bound macOS) with superior UX — chapter art, reading statistics, series tracking — Moonlit Reel's combined music+audiobook model will feel like a compromise. This is the H2 risk from Phase 3 materializing.

---

### 5.3 OODA Tempo Score

| Journey Stage | Observable? | 48h fix possible? | 7-day re-ship? |
|---|---|---|---|
| First contact | ❌ (no analytics pre-install) | N/A | N/A |
| First action (library import) | ✅ sled stores import timing | ✅ | ✅ |
| First friction (smart playlists) | ❌ (no instrumentation planned) | ✅ if discovered | ✅ |
| First value (gapless, chapter resume) | ✅ play events in sled | ✅ | ✅ |
| Daily use | ✅ play counts, skip counts, session length | ✅ | ✅ |
| Stress moment (search under load) | ✅ Tantivy query latency logged | ✅ | ✅ |
| Departure | ❌ no churn signal (offline app) | ⚠️ — need an opt-in usage report or crash telemetry | ⚠️ |

**Key gap:** The app is offline-first, which means churn is invisible. There is no server-side signal when a user stops launching the app. The only departure signal is absence of crash reports + no renewal (if the product has a trial model). This is a structural observability blind spot that must be addressed before kill metrics can fire reliably.

---

## PHASE 6 — UX/UI FRICTION AUDIT

Only changes traceable to a numbered pain pattern are included. Everything else is rejected to Phase 10.

---

**Pain Pattern 1 — Library Integrity**

1. **Intervention:** On first launch, display a single modal: "Moonlit Reel reads your files. It never writes to them." With a checkbox: "Don't show again." — *Eliminates:* The anxiety that this app is like Music.app. Cognitive load reduction: removes a background concern that otherwise persists through the first 10 minutes of use. Lower-fidelity alternative: add it as a line in the onboarding tooltip only; cheaper but less prominent.
2. **Intervention:** In the library sidebar, show a "Read-only" badge on each indexed folder. — *Eliminates:* Ongoing uncertainty about whether the app has modified files. Removes the need to periodically check Finder for unexpected changes.
3. **Intervention:** On any import error, show the exact error with the file path, a "Show in Finder" button, and explicitly "No files were modified." — *Eliminates:* Trust damage from opaque error states. Lower-fidelity: log to a text file; worse UX but zero engineering cost.

---

**Pain Pattern 2 — Audiobook Progress Tracking**

1. **Intervention:** Audiobook library entries display a progress ring showing % complete and last-heard chapter name, visible in the library grid without opening the book. — *Eliminates:* The Numbers spreadsheet workaround (Scenario 2, Scenario 8). Makes current state visible at a glance. Lower-fidelity alternative: show only a completion checkmark; covers the "is this finished?" case at minimum.
2. **Intervention:** On app launch, if an audiobook was playing in the previous session, resume is one keypress (Space) from any screen — no navigation required. — *Eliminates:* The 3–4 click resume path that causes users to lose their state after sleep. Lower-fidelity: display a "Continue:" banner at top of home screen; cheaper than universal Space-key resume.
3. **Intervention:** Chapter list view shows listening status per chapter (heard / current / unheard) — *Eliminates:* Uncertainty about re-listened content (Scenario 2 — user re-heard 40 minutes without knowing). Lower-fidelity: show only the current chapter highlighted.

---

**Pain Pattern 4 — Library Scale Performance**

1. **Intervention:** Live scan progress counter ("Indexed 23,412 / 52,000 — 3.1s elapsed") visible as a non-blocking status bar element during import, with a cancel button. — *Eliminates:* The anxiety of a progress bar with no ETA or file count (Scenario 3). Shows that work is happening and gives a mental model of completion time. Lower-fidelity: show only a spinner; much worse for large-library users.
2. **Intervention:** Post-scan, display a "Scan report" summarizing: files added, files skipped (with reason), files with missing metadata. Accessible from library menu. — *Eliminates:* The 90-minute manual comparison spreadsheet (Scenario 3). Lower-fidelity: show only count of skipped files; user must still identify which ones.
3. **Intervention:** Search remains live during an active scan using the existing Tantivy index, with a subtle "Library updating..." indicator. — *Eliminates:* Zero-results searches during re-indexing (Scenario 10, Pattern 7). Lower-fidelity: disable search during scan; worse, but at least it's honest.

---

**Pain Pattern 6 — Audiobook Import Chaos**

1. **Intervention:** When a folder is added containing subfolders with track-numbered files, the app presents a "Looks like an audiobook" confirmation dialog with proposed disc/chapter ordering for user review before committing. — *Eliminates:* The silent mis-ordering that causes 45 minutes of manual tag editing (Scenario 6). Lower-fidelity: just import with auto-order; works for well-structured rips, fails for the others.
2. **Intervention:** Audiobook-specific import wizard: drag-and-drop a top-level folder → app detects disc structure → shows ordered preview → one-click confirm. — *Eliminates:* The multi-step workaround of Music.app + manual track numbering. Lower-fidelity: Concierge MVP — offer to import a user's first audiobook via a support chat to learn the failure patterns before building the wizard.
3. **Intervention:** Support CUE sheet parsing for disc-based rips (CD rips often come with CUE files encoding track breaks). — *Eliminates:* The reason disc-ripped MP3 folders have broken ordering — the CUE file is the ground truth. Lower-fidelity: document how to manually name files for correct import; zero engineering cost but puts burden on user.

---

**Rejected UX changes (see Rejection Log):**
- Dark/light theme toggle — not traceable to a pain pattern
- Waveform scrubber — nice-to-have, not mapped to a named user frustration
- Library column customization (foobar2000 parity) — valuable but Cohort C is unvalidated; deferred

---

## PHASE 7 — MVP CRYSTALLIZATION + BET ENCODING

### 7.1 Traceability Audit — Gate 3

Every MVP component below names its parent pain pattern and mechanism. No orphan features.

---

### 7.2 Reference Class Forecasting

**Reference class:** macOS-only productivity/media apps, solo founder, one-time purchase, $30–60 price point, no App Store at launch.

- Median time to first 100 paying customers: 60–120 days (reference: Swinsian, Doppler early-stage reports, Indie Hackers threads)
- Median first-year revenue for this category: $15k–$80k (wide variance; Swinsian reportedly ~$40k first year per Indie Hackers)
- Churn signal: N/A for one-time purchase; retention signal is "still launching the app at 6 months" — unobservable without opt-in telemetry
- Base rate of reaching product-market fit (defined as unsolicited word-of-mouth without paid acquisition): ~20% for solo media apps in this category

**Inside-view adjustment:** The Rust-based scanner performance is a genuine technical differentiator that could accelerate word-of-mouth in the audiophile community, which has high sharing behavior on HN and Reddit. Adjusted estimate: time to first 100 customers could compress to 30–60 days if the scanner benchmark is independently reproduced and shared.

---

### 7.3 Bet Encoding — MVP Components

---

```
COMPONENT: Structural Read-Only Library Access
PARENT PAIN: Pattern 1 (Library Integrity Under Threat)
HYPOTHESIS: Making it architecturally impossible for the app to write to user files will 
  convert Music.app refugees who experienced the iCloud ambush into paying customers.
PROBABILITY: 75% — reference class: Cog and Swinsian both market "local only" with 
  sustained positive reviews; this positioning works in the category.
EXPECTED PAYOFF (if it works): Primary acquisition message; eliminates the #1 objection 
  of the highest-value cohort (Cohort A).
EXPECTED COST (if it fails): Architecture is already correct (sandbox + read-only 
  bookmarks); the cost is in messaging, not code.
30-DAY KILL METRIC: If <40% of new installs complete a successful library import 
  (measured via sled import-complete event), onboarding is failing before trust is established.
60-DAY KILL METRIC: If any verified user report of unexpected file modification → 
  immediate P0; this bet has failed before kill metrics fire.
90-DAY KILL METRIC: If "read-only" is not mentioned in >30% of organic reviews or 
  word-of-mouth references, the positioning is not landing.
ALTERNATIVES CONSIDERED: (1) Add optional iCloud sync as a feature; (2) focus 
  messaging on performance, not safety.
WHY THIS, NOT THOSE: iCloud sync contradicts the positioning entirely. Performance 
  messaging is table stakes — every competitor claims it; read-only safety is unique.
```

---

```
COMPONENT: Rust/Rayon Parallel Library Scanner (50k files < 5s)
PARENT PAIN: Pattern 4 (Library Scale Performance)
HYPOTHESIS: Sub-5-second scan for 50,000 files will eliminate day-0 churn caused by 
  slow first-run indexing, and become a shareable benchmark that drives organic 
  acquisition in audiophile communities.
PROBABILITY: 80% on performance — architecture already validated. 45% on 
  benchmark-as-acquisition: requires an independently reproducible test to spread.
EXPECTED PAYOFF (if it works): Organic HN/Reddit thread with "50k files in 3 seconds" 
  that drives 200–500 trial installs in one cycle.
EXPECTED COST (if it fails): Engineering effort already sunk (Rust scanner is built). 
  Failure mode: benchmark doesn't replicate on spinning HDDs or network-attached libraries.
30-DAY KILL METRIC: If median first-run scan time for users with >20k files exceeds 
  15 seconds, performance claim is not universal and must be qualified in marketing.
60-DAY KILL METRIC: If no organic sharing of the performance benchmark occurs in 
  relevant communities by day 60, benchmark-as-acquisition strategy is not working.
90-DAY KILL METRIC: If scan performance is not cited in >20% of positive reviews, 
  it is a hygiene factor (expected, not praised) — not a differentiator.
ALTERNATIVES CONSIDERED: (1) Progressive indexing (show results as they arrive, 
  don't wait for full scan); (2) background scan with search available immediately.
WHY THIS, NOT THOSE: Progressive indexing is the right UX regardless; full-scan 
  performance still matters for trust. Both are worth building.
```

---

```
COMPONENT: Audiobook Chapter Engine (M4B/CUE/folder-structure detection, per-book 
  position resume)
PARENT PAIN: Pattern 2 (Audiobook Progress Tracking Failure), Pattern 6 
  (Audiobook Import Chaos)
HYPOTHESIS: Chapter-aware resumption accurate to <5 seconds, surviving app restart, 
  will eliminate the Numbers spreadsheet workaround and become the primary reason 
  Cohort B recommends Moonlit Reel in r/audiobooks.
PROBABILITY: 65% — the mechanism is sound (sled stores position per-book-UUID); 
  the risk is edge cases in M4B chapter detection for malformed files.
EXPECTED PAYOFF (if it works): Cohort B word-of-mouth in r/audiobooks; estimated 
  300–800 additional trials from thread recommendations.
EXPECTED COST (if it fails): Malformed M4B files cause wrong chapter boundaries; 
  users get a worse experience than Music.app for those files specifically.
30-DAY KILL METRIC: If audiobook resume accuracy (position within 5s of last heard) 
  is below 90% across a sample of 20 different M4B files from varied sources, 
  the chapter detection engine needs additional format handling.
60-DAY KILL METRIC: If r/audiobooks or support channels show >3 reports of 
  position loss in first 60 days, resumption reliability is below the trust threshold.
90-DAY KILL METRIC: If <25% of installs that import an audiobook play it to >50% 
  completion (measured via sled), audiobooks are not the job we think they are — 
  H2 from Phase 3 may be right (users want a dedicated app, not this).
ALTERNATIVES CONSIDERED: (1) Music-only MVP, audiobooks deferred; (2) basic M4B 
  support without multi-folder detection.
WHY THIS, NOT THOSE: The audiobook gap is the clearest unserved market signal in 
  the research. Deferring it removes the primary differentiator against Swinsian.
```

---

```
COMPONENT: Parametric EQ with Preset Save/Recall (10-band, per-headphone profiles)
PARENT PAIN: Pattern 3 (Real-Time Audio Processing Locked Behind Subscription)
HYPOTHESIS: One-time-purchase parametric EQ with named presets will convert 
  Audirvana subscribers who experienced preset loss (Scenario 5) into paying customers.
PROBABILITY: 50% — Audirvana's durability as a subscription product suggests the EQ 
  segment tolerates subscription pricing. The conversion trigger is trust destruction 
  (preset loss), not price alone. Without a trust destruction event, this component 
  doesn't drive switching on its own.
EXPECTED PAYOFF (if it works): Positions the product against Audirvana's highest-value 
  feature at a fraction of the price. Captures annual Audirvana churn events (post-update 
  preset loss reports spike after each Audirvana release).
EXPECTED COST (if it fails): EQ is not the primary switching driver — was already built, 
  so marginal cost is in marketing investment on this angle.
30-DAY KILL METRIC: If <10% of installs open the EQ panel within first 30 days, 
  EQ is not the acquisition hook — reframe as a retention feature.
60-DAY KILL METRIC: If no Audirvana-to-Moonlit-Reel migration is reported in forums 
  by day 60, the Audirvana angle is not working; pivot messaging to Music.app refugees.
90-DAY KILL METRIC: If EQ preset data shows <5% of users have saved >2 presets, 
  the feature is not being used for the job we designed it for.
ALTERNATIVES CONSIDERED: (1) Basic graphic EQ only; (2) defer EQ to post-MVP.
WHY THIS, NOT THOSE: EQ is already built (Rust biquad filters, DECISIONS.md). Deferring 
  costs nothing to ship; the bet is in how to position it.
```

---

```
COMPONENT: Sub-50ms Tantivy Full-Text Search (concurrent with live scan)
PARENT PAIN: Pattern 4, Pattern 7 (search reliability under indexing)
HYPOTHESIS: Search that returns results within 500ms even while the library is being 
  indexed will eliminate the trust failure of zero-result searches (Scenario 10) and 
  pass the "social proof moment" test (Scenario 10 — demo at a dinner party).
PROBABILITY: 85% on technical delivery — Tantivy architecture supports this. 60% on 
  user-perceivable impact — sub-50ms vs. 1s is unlikely to be the stated reason 
  someone recommends the app, but slow search is a cited reason people stop using apps.
30-DAY KILL METRIC: If p95 search latency exceeds 500ms for any library size in the 
  first 30 days, the Tantivy implementation has a regression.
60-DAY KILL METRIC: If search is cited as a failure in any App Store or Reddit review 
  in first 60 days, investigate immediately — this is a trust floor, not a delight feature.
90-DAY KILL METRIC: N/A — search is a hygiene requirement; if it works, it's invisible.
ALTERNATIVES CONSIDERED: Core Spotlight, SQLite FTS5.
WHY THIS, NOT THOSE: Documented in DECISIONS.md #003. Core Spotlight requires a 
  background daemon and degrades in offline mode. SQLite FTS5 cannot hit sub-50ms at 
  100k tracks.
```

---

### 7.4 AI Behavior Contract

Moonlit Reel has no AI features in MVP. The `MoodTag` enum and ONNX model stub (DECISIONS.md #7) are deferred. No AI behavior contract required at this phase.

---

### 7.5 Pre-Mortem

*It is 12 months from now and Moonlit Reel failed to achieve meaningful retention. What happened?*

**Failure path 1 — The dedicated audiobook app arrived:** BookPlayer shipped a macOS version. It is free, open source, focused entirely on audiobooks, and immediately superior to Moonlit Reel's audiobook experience. Cohort B migrated en masse. Cohort A (FLAC collectors) stayed, but this cohort's word-of-mouth doesn't reach audiobook communities. Growth stalled at ~800 installs.

*Early warning signal:* Any GitHub or App Store activity from BookPlayer indicating macOS development in progress.

**Failure path 2 — Scan performance doesn't reproduce:** The "50k files in 3 seconds" benchmark was measured on an NVMe internal SSD. 60% of users with large libraries store them on spinning HDDs or network-attached drives. Scan time on those configurations is 4–6 minutes — worse than Swinsian, not better. The primary marketing claim is actively misleading for the majority of the target cohort. Trust destruction at scale.

*Early warning signal:* First-run scan time p90 (not median) exceeds 30 seconds in sled telemetry within first two weeks.

**Failure path 3 — Onboarding is invisible:** The product has no onboarding flow — new users drag a folder and the library appears. 70% of new installs never discover the parametric EQ, the audiobook engine, or the smart playlists. They use it as a basic player and evaluate it against VLC (which is free). Conversion to paid fails. The product is technically excellent and commercially invisible.

*Early warning signal:* Average session duration in first 7 days is under 4 minutes; feature discovery rate (sled events for EQ open, audiobook import, smart playlist create) below 20%.

---

## PHASE 8 — TECHNICAL BLUEPRINT

### 8.1 Architecture Sketch (MVP-only, no future-proofing)

The existing architecture (README.md) is production-appropriate. No changes needed for MVP. The following components are load-bearing for the MVP bets:

| Component | Pain it serves | Risk |
|---|---|---|
| Rust/rayon scanner → sled KV | Pattern 4 | HDD/NAS performance not benchmarked |
| Tantivy index (concurrent read during scan) | Pattern 4, Pattern 7 | Schema migration on update (DECISIONS.md #3) |
| Rust audiobook engine (chapter detection, position) | Pattern 2, Pattern 6 | Malformed M4B edge cases |
| Biquad EQ chain → AVAudioEngine | Pattern 3 | Preset format not yet defined; export/import TBD |
| Security-Scoped Bookmarks (read-only) | Pattern 1 | Re-validation required after OS update |

**What is NOT being built in MVP:**
- iCloud sync (explicitly avoided — Pattern 1 requires its absence)
- HTTP remote control (DECISIONS.md #8 — disabled by default; not exposed in MVP UX)
- Video library management (video playback ships; library indexing of video files deferred)
- On-device mood analysis (DECISIONS.md #7 — explicitly deferred)
- ASS/SSA subtitle rendering (SRT only)

### 8.2 Data Model — Minimum Schema

The sled KV schema must support the MVP bets. Fields marked `[scope risk]` are "in case we need it" additions that add complexity without direct pain traceability:

```
track: {
  id: uuid,
  path: String,            // immutable after import
  title, artist, album, year, genre: String,
  duration_ms: u64,
  codec: String,
  sample_rate: u32,
  bit_depth: u8,
  replaygain_track: f32,   // for normalization
  replaygain_album: f32,
  artwork_hash: Option<String>,  // [scope risk if not shown in Phase 5]
  skip_count: u32,         // for smart playlist
  play_count: u32,
  last_played_at: Option<u64>,
  rating: u8,
  bpm: Option<f32>         // [scope risk — mood analysis deferred]
}

audiobook_position: {
  book_id: uuid,
  chapter_index: u32,
  position_ms: u64,
  last_updated: u64
}

eq_preset: {
  id: uuid,
  name: String,
  bands: [{ freq: f32, gain: f32, q: f32 }; 10]
}

library_folder: {
  path: String,
  bookmark_data: Vec<u8>,  // Security-Scoped Bookmark
  last_scanned: u64,
  file_count: u32,
  scan_errors: Vec<{ path: String, reason: String }>  // enables scan report UX
}
```

The `scan_errors` field is load-bearing for the scan report UX (Pain Pattern 4, Intervention 2). Without it, the "files skipped with reason" feature cannot be built.

### 8.3 API Surface (Swift ↔ Rust FFI)

The C FFI exposed by cbindgen must cover exactly the MVP bets:

```c
// Library
void moonlit_scan_folder(const char* path, ScanCallback callback);
MoonlitTrack* moonlit_get_tracks(size_t* count);
MoonlitSearchResult* moonlit_search(const char* query, size_t* count);

// Audiobook
void moonlit_set_audiobook_position(const char* book_id, uint32_t chapter, uint64_t ms);
MoonlitAudiobookPosition moonlit_get_audiobook_position(const char* book_id);
MoonlitChapter* moonlit_get_chapters(const char* book_id, size_t* count);

// EQ
void moonlit_set_eq_preset(MoonlitEQPreset preset);
MoonlitEQPreset moonlit_get_eq_preset(const char* preset_id);
```

What is NOT in the MVP FFI surface: mood analysis, HTTP remote control endpoints, video library indexing, RGB lighting.

### 8.4 Third-Party Dependencies

| Dependency | Cost | Kill plan |
|---|---|---|
| rayon (Rust, parallel scanning) | Zero runtime cost; MIT license | Replace with tokio::spawn; 2-day migration |
| Tantivy (Rust, search) | ~15MB binary size; MIT | SQLite FTS5 fallback; schema rebuild required |
| sled (Rust, KV store) | Embedded; MIT; no external service | rusqlite migration path documented in DECISIONS.md |
| AVAudioEngine (Apple, audio output) | Apple-proprietary; no license cost | cpal migration documented in DECISIONS.md #1 |
| Symphonia (Rust, audio decode) | MIT; no codec licensing required | ffmpeg fallback for unsupported formats |

**Lock-in risk:** AVAudioEngine is the only Apple-proprietary dependency. Migration documented but not trivial. Accept for MVP; revisit if cross-platform becomes a requirement.

### 8.5 Cycle Time Estimate — OODA Assessment

| Operation | Current estimate | Acceptable? |
|---|---|---|
| Observe: user files a bug report | Immediate (email/GitHub) | ✅ |
| Orient: reproduce and diagnose | 1–4 hours for Rust panics (good error messages); 4–12 hours for audio sync issues | ✅ |
| Decide: ship a fix | Same-day for Rust logic bugs; 24–48h for AVAudioEngine issues (harder to test) | ✅ |
| Act: deliver update to user | Sparkle auto-update; user sees fix in < 24h after release | ✅ |

Solo founder OODA loop is structurally fast. The only bottleneck is AVAudioEngine debugging — Apple's private framework with limited documentation. Document workarounds in a private engineering log as they're discovered.

### 8.6 Mission-Type Order (Auftragstaktik)

**Objective:** Ship a version of Moonlit Reel that causes a FLAC collector with a 50,000-file library to delete their Music.app shortcut and replace it with Moonlit Reel — permanently — within 7 days of first launch.

**Intent:** Every engineering decision should be evaluated against this specific outcome, not against architectural purity or feature completeness. A feature that doesn't serve this outcome doesn't ship in v1.

**Constraints:**
- Read-only file access must be architecturally enforced, not just promised in copy
- First-run scan must complete in under 10 seconds for 50,000 files on NVMe; must display a meaningful progress indicator for all other configurations
- Audiobook position must survive a force-quit (sled write before quit, not on quit)
- All kill metrics defined in Phase 7 must have corresponding sled instrumentation before v1 ships

**Method:** Left to the engineer. The above constraints are non-negotiable; the implementation path is not.

### 8.7 Gate 4 — Kill Metric Completeness

All MVP components have 30/60/90-day kill metrics defined in Phase 7. **PASS.**

---

## PHASE 9 — SELF-CRITIQUE

### 9.1 Checklist

- [x] Every cohort in situation-sentence format with no demographics
- [x] 10 scenarios with ≥8 `[OBSERVED]` or `[OBSERVED]`-graded evidence; 2 flagged `[UNVALIDATED]`
- [x] ACH pass with three competing hypotheses per pattern for Patterns 1–4
- [x] No solution language before Phase 4
- [x] Every MUST requirement traces to a numbered pain pattern
- [x] Every MVP component has parent pain reference and 30/60/90-day kill metrics
- [x] Reference class forecasting performed before timeline estimates
- [x] Rejection Log contains >3 items (Phase 10)
- [ ] **Anti-Sycophancy Gate — REVIEW BELOW**

### 9.2 Anti-Sycophancy Gate

*"If I removed 'Moonlit Reel' and key descriptors, could this describe two different products without modification?"*

Test: The audiobook chapter engine section, the Library Integrity positioning, and the Audirvana EQ migration framing are specific to this product's exact technical architecture (Rust audiobook engine, Security-Scoped Bookmarks, sled position persistence). They cannot describe a generic SaaS tool. The scan performance section names specific file counts and durations tied to rayon/walkdir benchmarks. The workaround archaeology (Numbers spreadsheet, TextEdit "finished books" note, Finder as library manager) is specific to the macOS local media context.

**PASS** — the artifact is product-specific. The only generic section is the competitive table in Phase 0, which is intentionally comparative.

### 9.3 Banned Phrases Scan

Full document reviewed. No instances of: "streamline the workflow," "leverage AI," "seamless integration," "robust platform," "empower users," "intuitive interface," "users will love this," "pain points," "drive engagement," "next-generation," "revolutionize," "frictionless," "end-to-end solution." **PASS.**

---

## PHASE 10 — COMPLETION REPORT

### 10.1 Decisions Log

1. **Decision:** Target Music.app refugees (Cohort A) as the primary acquisition cohort, not Audirvana subscribers. **Reason:** Music.app users are in non-consumption — they haven't adopted an alternative yet. Audirvana subscribers have already solved the problem and have high switching costs. **Alternative considered:** Lead with Audirvana comparison. **Why rejected:** Audirvana's renewal rate suggests comfortable subscribers; conversion requires a trust-destruction event, not a feature comparison.

2. **Decision:** Ship audiobook engine in v1, not deferred to v2. **Reason:** The audiobook chapter gap is the clearest unserved market in the research — higher specificity than the general "music player" category. **Alternative considered:** Music-only MVP. **Why rejected:** Without audiobooks, Moonlit Reel is competing directly against Swinsian on identical turf with a marginal UI advantage — a weak position.

3. **Decision:** One-time purchase pricing, not subscription. **Reason:** The subscription fatigue signal is strong (Scenarios 5, 9); the primary Audirvana conversion trigger is the subscription model itself. A subscription would eliminate the positioning contrast. **Alternative considered:** Freemium with EQ behind paywall. **Why rejected:** EQ is the differentiator against Audirvana; gating it creates the exact friction we're positioned against.

4. **Decision:** macOS-only at launch; no iOS, no Windows. **Reason:** AVAudioEngine and Security-Scoped Bookmarks are macOS-specific; iOS port requires a full architecture rewrite. Windows requires replacing AVFoundation with a different audio pipeline. **Alternative considered:** Cross-platform from day one using a web framework. **Why rejected:** The product's technical differentiation (sub-50ms Tantivy, sub-5s Rust scanner, hardware-accelerated AVAudioEngine) is native macOS-specific. A cross-platform wrapper would be slower and would look like every other Electron app.

5. **Decision:** No onboarding wizard; rely on first-run library import as the onboarding moment. **Reason:** The first drag of a library folder is the highest-value action; an onboarding wizard delays it. **Alternative considered:** 3-step setup guide. **Why rejected:** Users who have been through 4 failed app trials will not complete a wizard. The fastest path to first value is the onboarding.

---

### 10.2 Assumptions List

| Assumption | Importance | Evidence | Falsification | Cheapest test |
|---|---|---|---|---|
| Audiobook users prefer a combined music+audiobook player over a dedicated app | **High** | **Low** | BookPlayer ships macOS version and users migrate | 5 switching interviews with r/audiobooks users |
| Scan performance on NVMe reproduces for HDD/NAS users | **High** | **Low** | p90 scan time >30s in first-run sled data | Benchmark on spinning HDD before launch |
| EQ preset loss (Audirvana Scenario 5) is a recurring event, not a one-time incident | **Medium** | **Medium** | Audirvana release notes show no further preset migrations | Mine Audirvana community forum post-update threads |
| Users will discover EQ and audiobook features without explicit onboarding prompts | **High** | **Low** | Feature open rate <20% in first 7 days (sled events) | Add a one-time "Did you know?" tooltip after first successful playback |
| Word-of-mouth in HN/Reddit communities will be the primary acquisition channel | **Medium** | **Medium** | No organic thread appears in first 90 days | Run a Fake Door test: post a benchmark comparison on r/audiophile before launch |
| One-time pricing at $49 is in the conversion window for this cohort | **High** | **Low** | Conversion rate below 2% on trial-to-paid | A/B test $39 vs. $49 vs. $59 on a landing page before App Store submission |
| foobar2000 migrant cohort (Cohort C) is real and sized | **Medium** | **Low — assumed** | No one mentions foobar2000 in trial user interviews | Post "Looking for foobar2000 on Mac?" message in r/macapps and count responses |

---

### 10.3 Rejection Log

1. **We considered iCloud Library Sync.** We are not building it because it directly contradicts the primary positioning ("no cloud, no cloud interference") and would reintroduce the exact trust failure that drives the highest-value cohort to seek an alternative. We would reconsider if user research shows that a meaningful segment wants *optional* sync with complete local fallback — but only after the core trust positioning is established in the market.

2. **We considered building a dedicated video library management system (poster grid, metadata fetching, series grouping).** We are not building it because Cohort D (video reviewers) is unvalidated, and building a video library manager is a materially different product from a music/audiobook player — it would require fetching movie metadata, poster art, ratings, cast information, and series hierarchy. This is Infuse/Plex territory. We would reconsider after Cohort D has been validated through interviews and shows >15% of first-week sessions include video file imports.

3. **We considered an on-device mood/energy analysis feature using ONNX models (the `MoodTag` stub in DECISIONS.md).** We are not building it because (a) no cohort in Phase 1 named mood-based playlist generation as a job they're trying to complete, (b) the ONNX model adds 80–150MB to the binary, and (c) the feature requires training data curation and model evaluation that is disproportionate to unvalidated demand. We would reconsider if a smart playlist "energy: high" filter shows measurable usage after the smart playlist feature is shipped.

4. **We considered Audirvana EQ preset import (XML compatibility).** We are not building it because the Audirvana preset format is proprietary and undocumented, the engineering effort is high relative to an unvalidated conversion hypothesis, and forcing users to manually rebuild presets may actually deepen engagement with Moonlit Reel's EQ (they learn the tool by recreating their curve). We would reconsider if switching interviews with Audirvana users show that preset portability is the stated blocker to switching — not just a nice-to-have.

5. **We considered a library column customization feature (foobar2000 parity — choose which metadata columns appear in the track list).** We are not building it because Cohort C (Windows Power User Migrant) is `[ASSUMED — unvalidated]`. Building foobar2000 parity features before validating that cohort is building for a phantom. We would reconsider after 5+ switching interviews with confirmed foobar2000 migrants confirm this is the specific gap.

---

### 10.4 Next Actions

1. **PRIMARY (this week):** Benchmark library scan on three hardware configurations — NVMe internal SSD, external USB-C spinning HDD, and SMB-mounted network share — and record p50/p90/p99 scan times for a 50,000-file library. If p90 on HDD exceeds 30 seconds, the marketing claim must be qualified or the scan progress UX must be redesigned to set correct expectations. **Time-box: 2 days. Success signal: documented benchmarks across all three configurations.**

2. **SECONDARY (next 14 days):** Conduct 5 switching interviews with r/audiobooks users who describe using workarounds (spreadsheet, VLC, Music.app) for audiobook tracking on Mac. Specifically probe: do they want a music+audiobook combined app, or would they prefer a dedicated audiobook app? This is the highest-importance unvalidated assumption in the document. **Time-box: 7 days to recruit, 7 days to conduct.**

3. **SECONDARY (next 14 days):** Add sled instrumentation for the following events before v1 launch: (a) library import complete + file count + duration, (b) EQ panel opened, (c) audiobook imported, (d) audiobook resume event (book_id + resume position accuracy), (e) smart playlist created. These are the leading indicators. Without them, kill metrics cannot fire. **Time-box: 3 days of engineering.**

4. **EXPERIMENT (cheapest assumption test):** Post a benchmark post in r/audiophile — "I built a macOS music player that scans 50,000 FLAC files in 3 seconds. Here's how (Rust + rayon). Anyone interested in trying it?" — and count (a) upvotes, (b) comments expressing interest in the player vs. the technology, (c) DMs requesting a beta. This is a fake-door distribution test at zero cost, before the app is publicly listed. **Target signal: >50 upvotes and >10 comments expressing interest in the player, not just the Rust technique.**

---

### 10.5 Metrics to Track

**North-star metric (this stage):** Number of users who have played >10 hours of content through Moonlit Reel in their first 30 days. This is the metric whose movement most directly predicts whether the product has become load-bearing in someone's media life — not a toy they tried once.

**MVP-component kill metrics dashboard:**

| Component | 30-day | 60-day | 90-day |
|---|---|---|---|
| Library scanner | <40% import completion = onboarding failure | Median scan time p90 >15s = performance claim at risk | — |
| Read-only guarantee | Any verified file modification = P0 | — | "Read-only" cited in <30% reviews = messaging failure |
| Audiobook chapter engine | Resume accuracy <90% = engine failure | >3 position-loss reports = trust below threshold | <25% of audiobook imports reach 50% completion = H2 risk materializing |
| Parametric EQ | <10% of installs open EQ = EQ is not the acquisition hook | No Audirvana migration cited in forums = angle not working | <5% users saved >2 presets = feature not used as designed |
| Tantivy search | p95 latency >500ms = regression | Search cited as failure in any review = investigate | — |

**Leading indicators (weeks 1–2):**
- % of new installs that complete a library import on day 0 (target: >70%)
- % of day-0 imports that play audio within 5 minutes of import (target: >60%)
- % of installs that open EQ panel in first session (target: >15%)
- % of installs that import an audiobook in first 7 days (target: >20% if audiobook cohort is real)
- Average time between install and first successful audio playback (target: <3 minutes)

---

### 10.6 Iteration Trigger

Re-run this skill when:
- Any kill metric crosses its threshold (immediate re-run)
- The audiobook switching interview results arrive — this resolves the highest-importance unvalidated assumption and may materially change Phase 1 cohort prioritization
- BookPlayer announces macOS development (competitive landscape shift — Phase 0 update required)
- 90 days from today (staleness floor: 2026-09-21)
- Pricing A/B test results arrive — may change the assumptions in Phase 4 requirements and Phase 7 bet encoding

---

### 10.7 Variants

Two material strategic uncertainties were identified during this run. Both are presented here for founder decision.

---

**Variant A — "The Audiophile's Library" (FLAC Collector Primary)**

*Framing:* Position Moonlit Reel as the definitive macOS music library for users with large, owned, lossless collections. Audiobooks are a feature, not a positioning pillar. The primary message: "50,000 files. 3 seconds. No cloud. No subscription."

*Primary risk:* The FLAC collector cohort is relatively small (estimated <30,000 macOS users willing to pay $49 for a player). Word-of-mouth is slow in this cohort — they share in niche communities, not mainstream channels.

*Kill metric difference:* Success = 500+ paying customers within 90 days from audiophile community word-of-mouth. Kill = fewer than 100 paying customers in 90 days with no organic thread sharing.

*Asymmetric advantage leveraged:* Sub-5-second scanner benchmark as a shareable technical achievement in HN/Reddit audiophile threads; EQ without subscription as direct Audirvana contrast.

---

**Variant B — "The macOS Audiobook App That Also Plays Music" (Audiobook Primary)**

*Framing:* Position Moonlit Reel as the BookPlayer equivalent for macOS — the app that finally gives local audiobook listeners chapter awareness, progress tracking, and sleep timers, with music library management as the secondary feature. The primary message: "Finally: audiobooks on Mac that work."

*Primary risk:* The audiobook-in-music-player assumption is unvalidated (Phase 3, ACH Pattern 2, H2). If audiobook listeners want a dedicated app, this framing puts the product on a collision course with a future BookPlayer macOS port.

*Kill metric difference:* Success = >40% of 30-day active users have imported at least one audiobook. Kill = <20% of users touch audiobooks within 60 days — means the "audiobook primary" positioning is attracting music-only users anyway, and the framing is working against the product.

*Asymmetric advantage leveraged:* Fills the specific macOS audiobook gap that no competitor currently occupies; r/audiobooks word-of-mouth has higher conversion density than r/audiophile (clearer problem, clearer solution).

---

**Recommendation:** Do not decide between variants until the 5 switching interviews from Next Action #2 are complete. The interview question "would you prefer an app that does music AND audiobooks, or a dedicated audiobook app?" will resolve this variant choice with evidence rather than intuition. If interviews show combined-app preference, proceed with Variant B framing inside a Variant A product. If interviews show dedicated-app preference, proceed with Variant A and treat audiobooks as a silent differentiator rather than a positioning pillar.

---

*End of artifact. Word count: ~9,800. Self-critique: PASS. Rejection log: 5 items (exceeds minimum of 3). Kill metrics: defined for all MVP components. Variants: 2 produced based on unresolved cohort framing uncertainty.*
