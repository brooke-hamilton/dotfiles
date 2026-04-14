---
description: "Review daily-planner reports and session logs for quality issues, then update the daily-planner agent with improvements"
agent: "agent-optimizer"
argument-hint: "Describe a feature or improvement to add to the daily-planner agent"
---

Analyze the daily-planner workflow and apply improvements. Use the input below to determine what to change.

## Requested Improvement

{{input}}

If no input is provided, default to a general quality review — find the most recent `daily-report-*.md` in `.copilot-tracking/` and the most recent session log, then identify areas for improvement.

## Analysis Steps

1. **Load all agent definitions** from `.github/agents/` and `.github/prompts/` before starting analysis.
2. **Find and load the daily report(s)** in `.copilot-tracking/daily-report-*.md`. Use the most recent by date in the filename.
3. **Find and load the session log** from `{{VSCODE_TARGET_SESSION_LOG}}` or a recent session log if available.
4. **Run the full analysis** covering template compliance, data quality, orchestration efficiency, prompt clarity, and output quality.
5. **Produce concrete recommendations** with before/after prompt text referencing exact files and lines.
6. **Apply approved changes** to the daily-planner agent definitions (`.github/agents/daily-planner.agent.md`, `.github/prompts/daily-plan.prompt.md`, and related subagent files) to implement the requested improvement.
