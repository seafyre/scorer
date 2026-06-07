# CLAUDE.md

## Project Overview

**Scorer** is a native iOS/iPadOS darts (X01) scoring app, pure SwiftUI, built by a solo dev. The whole app lives in one file: `Scorer/ContentView.swift` — Models (`Turn`, `Player`, `GameAction`), the `GameViewModel` (state + all game rules), every view, and the `Haptics`/`ThemeApplier` helpers. `Scorer/ScorerApp.swift` is just the `@main` entry point. There is no test target.

## Conventions

- **Keep new code in `ContentView.swift`** alongside its peers, unless a piece grows large enough to clearly warrant its own file.
- **MVVM split:** game logic (bust rules, leg/set/match cascade, checkout tables, stats) lives in `GameViewModel`; views stay thin and read from the VM. Don't put rules in views.
- **Organize with `// MARK: -`** section dividers; subviews are `private struct`s.
- **Persistence:** settings/names persist via UserDefaults using Combine `$published.sink` pipelines in `GameViewModel.init`, with keys as `private let ...Key` constants; theme/haptics use `@AppStorage`. Follow the existing pattern when adding persisted state.
- **Fire haptics from view actions** via `Haptics.*` (not from the VM).
- **`.monospacedDigit()`** on any displayed number; use the `.glass` / `.glassProminent` button styles for new buttons.

## Keep Docs Current

After every change, check whether `readme.md` or this `CLAUDE.md` is now stale or would benefit from an update, and update it if so:
- **`readme.md`** — when a feature ships, moves out of "To be developed," or the user-facing description changes.
- **`CLAUDE.md`** — when the architecture, conventions, or project facts above no longer match the code.

Keep edits surgical and don't invent content — only reflect what actually changed.

---

Behavioral guidelines to reduce common LLM coding mistakes.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

There's no test target, so verification is: the Xcode build succeeds, the relevant SwiftUI `#Preview` renders, and the change behaves correctly when run in the simulator. State concrete success criteria before coding:
- "Add a checkout" → "the new score shows the right finish in the player tile, and busts when it shouldn't finish"
- "Fix the bust bug" → "reproduce it in the simulator, confirm the fix, check undo still restores state"

Pure game-rule logic in `GameViewModel` (bust rules, the leg/set/match cascade, checkout lookups) is a good unit-test candidate **if** a Swift Testing/XCTest target is ever added — but don't add one unless asked.

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
