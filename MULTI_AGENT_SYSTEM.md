# Multi-Agent System

## Goal
Let the platform coordinate specialized agent phases internally while the user still experiences one live coding agent.

## Implemented Files
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/multi_agent_system.ts`
- `/Users/angelonartey/Desktop/ForgeAI/functions/src/index.ts`

## Current Logical Roles
- `planner`
- `context`
- `editor`
- `validator`
- `repair`
- `git`

These are logical agents, not separate user-visible chat participants.

## Why Logical Roles Instead Of Separate Public Agents
The app already has:
- one durable task record
- one repo lock
- one event timeline
- one approval flow

Splitting the runtime into logical roles lets the system:
- preserve one clean UX
- make handoffs explicit
- persist role history
- coordinate retries and validation more cleanly

without reviving a chat-thread or suggestion-first experience.

## Handoffs
The runtime now records role transitions such as:
1. planner -> context
2. context -> editor
3. editor -> validator
4. validator -> repair when failures occur
5. validator or repair -> git for follow-up actions

These summaries are persisted in task metadata as the logical agent timeline.

## Shared Memory
The logical roles share:
- repo execution memory
- focused modules
- explored paths
- hydrated paths
- validation history
- failure paths
- cost ledger
- follow-up plan

That means a repair pass does not restart from scratch as a new blind prompt.

## Current Practical Benefit
The current system is better thought of as:
- one physical distributed worker
- many logical agent roles inside that worker

This already gives the runtime:
- clearer planning
- stronger context handoffs
- better failure reuse
- more inspectable orchestration state

## Current Limits
- Logical roles are persisted in metadata, not yet separate worker executables or queue types.
- There is no public UI that exposes each role as a separate named sub-agent.
- The role system is orchestration state, not a general open-ended multi-agent chat substrate.
