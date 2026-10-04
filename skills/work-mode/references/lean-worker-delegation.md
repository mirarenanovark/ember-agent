# Delegating code to lean LLM workers (mira-dev harness class)

Rules for orchestrating cheap/small model lanes (glm-flash class, trove, ag/gemini-flash) writing code while the orchestrator integrates. Companion to the mira-dev-harness skill (lane commands, bench); this file is the job-design doctrine.

## Job-shape law

- Workers AUTHOR new small files well: give one file, one contract test, exact export shape. They CANNOT extend legacy multi-hundred-line files — they regenerate from scratch and gut existing exports even with EXTEND-only in the prompt. Observed repeatedly across models and lanes; treat as a law of the class, not a model quirk.
- Therefore: split legacy files into small modules YOURSELF, hand workers greenfield modules with their own contract gates, and do surgical integration of the legacy core yourself. Integration diffs are 20-line jobs; workers waste whole runs on them.

## Fire-script hygiene

- Pin `HARNESS_ROOT` in every fire script AND preflight before spending tokens: assert target repo clean, contract files exist, paths in spec match repo layout exactly. An unpinned run executes in the wrong repo; the worker then invents files from imagination (hallucinated a whole engine rather than report failure).
- One wrong path in the spec costs 5+ worker steps of path-hunting. Resolve the real layout first, then write the spec.

## Gate design

- Contract must pin behavioral invariants: known-result constants, delta arithmetic (e.g. energy -0.5 exactly), blocked-flag set/cleared, consume-nothing cases. A gutted implementation must FAIL the gate.
- Syntax-or-load gates are vacuous: a worker shipped DONE with zero bytes written through one. EMPTY_DIFF must require changes in the allowed files only — harness DB dirt otherwise counts as work.
- Contract require() should try both repo layouts (split modules, then legacy path) — a gate that crashes on import reads as worker failure and burns the run.
- Budgets for contract-fix loops: ~16 steps, ~900s wall. 12 steps starves recovery once gate failures begin.
- Read-guards must count shell readers too: cat, sed -n, head, tail, awk, and `node -e ...readFileSync` all bypass a read-action-only counter.

## Browser builds of CommonJS modules

- Node-style `require()` loaded via `<script>` dies silently in browsers: page renders, every value reads 0, buttons no-op (`require is not defined`). Node tests all pass; the defect only exists in the browser context.
- Fix: generate a require-free bundle — concatenate modules in dependency order, strip `module.exports` and `require` lines, expose one object with dual export (`module.exports` in node, `window.engine`-style global in browser).
- Smoke-test without a graphical browser: node + minimal DOM shim (stub `document.getElementById` returning objects with textContent/style/onclick, `window.addEventListener` invoking immediately), then assert rendered text CHANGES after simulating a click (call the captured onclick). Static render checks miss dead buttons.
