# Core/Managers/

## OVERVIEW
Core event management - event fetching, filtering, and automation triggers.

## FILES
| File | Lines | Role |
|------|-------|------|
| EventManager.swift | ~8k | Event fetching from EventKit, filtering, state management |
| ActionsOnEventStart.swift | ~7k | Automatic actions when meeting starts (join, notify, script) |

## EVENT FLOW
1. `EventManager` fetches events via EventKit (`EKEventStore`)
2. Filters events by calendar, time window, declined status
3. `ActionsOnEventStart` monitors for event start → triggers configured actions
