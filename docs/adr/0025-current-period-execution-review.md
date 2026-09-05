---
status: accepted
---

# Scope execution review to the current natural period

## Context

Together needs a review surface that helps a single user understand recent execution without turning task completion into a score, streak, analytics dashboard or automated coach. The former “计划复盘” mixed completed work, mutable current-task risk, several rate definitions and long-tail statistics. That weakened the page mission, made the default period unclear and produced too many competing visual summaries.

## Decision

Rename the surface to “执行回顾” and make it an intentional, read-only review of the current natural week or month through the reference time. Default to the week; expose the month through a native toolbar menu. Do not provide previous-period navigation, rolling windows, custom ranges or an all-time mode.

Classify ordinary, non-recurring tasks by their final completion time while they remain completed. Reopened tasks leave the sample until completed again; archiving preserves the original classification and permanent deletion removes it. Keep completion count as the broad result. Calculate first-plan fulfillment and postponed proportion only from complete lifecycle histories. Compare only these two rates with the previous natural period at matching local-calendar progress, and show each period’s matching count and sample denominator only when both periods have at least five valid samples for that metric. The natural-period end is exclusive, including when a shorter previous month is clamped.

Show at most three “值得回看” tasks. Give each task one reason using the priority reopened, postponed at least twice, then missed first plan. Select one representative of each available reason before filling any remaining slots from the ranked candidates. Link each row to the existing single-task lifecycle review. Do not generate action advice.

Render the page as one flat vertical scroll flow. Keep the native back affordance and period menu in the navigation bar, then open the content with a `34pt` editorial title, its date range and a quiet dotted divider before the natural-language summary. Show completion count separately from first-schedule matching counts and their valid denominator. Add a native read-only drill-down using the same snapshot’s completed items, sorted by final completion time with UUID ties; do not reuse completed history’s different filtering and archive-date ordering. Continue with schedule-change copy, optional count/denominator comparisons, representative rows and a collapsed methodology disclosure that explains default dates and actual comparison intervals. Use the page-specific `8 / 16 / 24 / 32 / 48pt` spacing progression and `11 / 14 / 17 / 22 / 34pt` type hierarchy. Do not introduce cards, grids, charts, gauges, metric icons, status colors or a permanent tinted background.

## Consequences

- The page answers one question clearly: what was completed in the current period, and where execution diverged from the first plan.
- Trend text remains comparable without penalizing a partial current week or month.
- Sparse data produces less UI: trends, noteworthy rows and nonessential sections disappear instead of being filled with weak signals.
- Users who need older-period browsing continue to use completed history; execution review is not a historical analytics archive.
- Current incomplete-task risk remains in the execution flow where action is possible, not in this retrospective surface.

## Alternatives considered

- “历史回顾” with past-period navigation: clearer as an archive, but duplicates completed history and weakens current-period decision value.
- A dashboard with completion time, final-plan punctuality, unscheduled count, risk lists and charts: denser, but creates competing definitions and a scorecard tone.
- Rolling 7 / 30 day ranges: statistically convenient, but less legible than natural calendar periods and harder to compare with a user’s weekly or monthly planning rhythm.
- Automatic recommendations: potentially useful later, but the current evidence set does not justify prescriptive guidance.
