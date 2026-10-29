<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# RECTGTN — the planner model behind `plan` / `replan`

**RECTGTN** stands for **R**elationship-**E**nabled **C**apability-**T**emporal
**G**oal-**T**ask-**N**etwork — the HTN (Hierarchical Task Network) planning
model exposed over MCP by the `plan` and `replan` tools.

`priv/schemas/rectgtn_domain.schema.json` is the authoritative shape — every
top-level key a document may use, exhaustively, enforced by
`Taskweft.JSONLD.Loader.validate/2` with `additionalProperties: false`. This
page is prose and rationale on top of it, not a restatement: `@context`,
`@type`, `name` (required), `description`, `version`, `source`, `enums`,
`variables`, `actions`, `methods`, `capabilities`, `todo_list` — see the
schema for each one's exact shape.

## The three task kinds

Everything in a domain's `todo_list` (and in each method's `subtasks`) is one
of three kinds. `todo_list` is GTPyHOP's own term for this exact heterogeneous
list — `find_plan(state, todo_list)` — a name that fits because it mixes
calls, goals, and multigoals, not one uniform thing:

| Kind | JSON-LD form | Meaning |
|------|--------------|---------|
| **`TwCall`** | a call array `[name, arg…]` | name in `actions` → a primitive that runs; name in `methods` → a compound task decomposed via `alternatives` |
| **`TwGoal`** | a `todo_list` entry `{"goal": [{"pointer", "eq"}, …]}` | desired `(pointer, value)` bindings, satisfied via goal methods |
| **`TwMultiGoal`** | a `todo_list` entry `{"multigoal": {…}}` | a set of bindings the planner backjumps over, choosing which to satisfy first |

## `TwCall` — call arrays

```json
{"@context": {"khr": "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
              "domain": "khr:planning/domain/"},
 "@type": "domain:Definition", "name": "demo",
 "variables": [{"name": "done", "init": {"a": false, "b": false}}],
 "actions": {"do_a": {"params": [], "body": [{"pointer/set": "/done/a", "value": true}]},
             "do_b": {"params": [], "body": [{"pointer/set": "/done/b", "value": true}]}},
 "methods": {"top": {"params": [], "alternatives": [{"name": "seq",
                                                     "subtasks": [["do_a"], ["do_b"]]}]}},
 "todo_list": [["top"]]}
```

Effects use `pointer/set`; guards use `{"eval": {"type": "math/<op>", …}}`.

## `TwGoal` — goals

A conjunction of desired `(pointer, value)` bindings, as a `todo_list` entry —
satisfied by a *goal method*, which is not a distinct concept: it's an
ordinary `methods` entry named after the state var it targets. There's no
separate `goals` key — a goal method (`TwGoalMethodFn`) is mechanically
identical to an ordinary method, invoked as `(state, [key, desired])` the
same way any method is invoked as `(state, args)`:

```json
{"@type": "domain:Definition", "name": "blocks",
 "methods": {"pos": {"params": ["block", "dest"],
                     "alternatives": [{"name": "stack_it", "subtasks": [["stack", "block", "dest"]]}]}}}
```

```json
{"@type": "domain:Problem", "name": "switch_goal",
 "variables": [{"name": "switch", "init": {"x": false}}],
 "todo_list": [{"goal": [{"pointer": "/switch/x", "eq": true}]}]}
```

Because it's an ordinary method, a problem may instead just call it directly
as a `TwCall`: `"todo_list": [["pos", "a", "table"]]`.

## `TwMultiGoal` — multigoals

```json
{"@type": "domain:Problem", "name": "switch_multigoal",
 "variables": [{"name": "switch", "init": {"x": false, "y": false}}],
 "todo_list": [{"multigoal": {"switch": {"x": true, "y": true}}}]}
```

A `todo_list` may freely mix call arrays, goal, and multigoal objects:
`"todo_list": [["move_one", "a", "table"], {"multigoal": {"pos": {"c": "b"}}}]`.

## Relationships and capabilities — one ReBAC graph

RECTGTN's "Relationship-Enabled" and "Capability" are the same engine: a
domain's `capabilities` object is compiled into a ReBAC (Relationship-Based
Access Control) graph — the same graph `Taskweft.ReBAC` (`taskweft_rebac`)
exposes standalone via `Taskweft.rebac_check/5`/`Taskweft.rebac_expand/4` —
and action guards are evaluated against it, so a capability requirement can
be a composed relation expression, not just a direct edge (ADR 0004).

A graph is `{"edges": [{"subject", "rel", "object"}], "definitions": {}}` —
field order matches the canonical Lean model's `⟨subject, RelationType,
object⟩` tuple (`Planner.Capabilities`); JSON keys are looked up by name, not
position, so this is purely for readability/consistency, not a wire format
requirement.
Relations are the core model's eight, the closed `RelationType` enum in
`Planner/Types.lean`: `OWNS`, `CONTROLS`, `DELEGATED_TO`, `HAS_CAPABILITY`,
`IS_MEMBER_OF`, `SUPERVISOR_OF`, `PARTNER_OF`, `IS_A`. A domain verb is not one
of them: the runtime takes any relation string, so a domain that needs
`CAN_ENTER` or `CAN_INSTANCE` writes it in its own graph's edges and guards
(RFD66606-2204's fleet domain is the worked case) and the core enum stays
closed.

```elixir
graph =
  Taskweft.ReBAC.new_graph()
  |> Taskweft.ReBAC.add_edge("alice", "team_x", "IS_MEMBER_OF")
  |> Taskweft.ReBAC.add_edge("team_x", "resource_1", "OWNS")

Taskweft.ReBAC.check_rel(graph, "alice", "OWNS", "resource_1")
# => true, via the IS_MEMBER_OF -> OWNS chain
```

Relation *expressions* compose beyond a single relation name: `union`,
`intersection`, `difference`, and `tuple_to_userset` (follow a `pivot_rel`
chain, e.g. membership, before checking the inner expression).

## Capabilities and temporal duration

A `TwCall`, `TwGoal`, or `TwMultiGoal` domain may add either or both.

**Capabilities** — a top-level `capabilities` object carries the domain's
relationship graph. This is a dedicated top-level key, not a variable:
structured/relational data gets its own namespaced slot, matching glTF
Interactivity's own convention for extension data that isn't a scalar/vector
value socket (e.g. `KHR_lights_punctual`'s
`/extensions/KHR_lights_punctual/lights`).

```json
"capabilities": {
  "graph": {"edges": [{"subject": "<entity>", "rel": "HAS_CAPABILITY", "object": "<cap>"}, ...],
            "definitions": {}}
}
```

`graph.edges` is the **single canonical representation**: an entity holding a
capability is one `HAS_CAPABILITY` edge, written out like every other relation.
There is no `entities` sugar, and there is no compiled sugar for action
requirements either — write the guard directly into the action's own body as an
ordinary `{"eval": {"type": "rebac/check", "rel": <relation>, "subject": <ref>,
"object": <cap>}}` step, the same mechanism every other action precondition
already uses. An agent qualifies if it's a *member of a
team* that holds the capability, not just a direct holder, by expressing
`rel` as a relation expression rather than a bare name:

```json
"capabilities": {
  "graph": {"edges": [{"subject": "alice", "rel": "IS_MEMBER_OF", "object": "flight_team"},
                      {"subject": "flight_team", "rel": "HAS_CAPABILITY", "object": "fly"}]}
},
"actions": {
  "a_fly": {"params": ["agent"],
            "body": [{"eval": {"type": "rebac/check", "rel": "HAS_CAPABILITY",
                                "subject": "{agent}", "object": "fly"}},
                      {"pointer/set": "/loc/{agent}", "value": "..."}]}
}
```

An action only applies to an agent for whom the guard holds; the planner
tries the next alternative otherwise (or reports no plan if none qualify).

**Temporal duration** — any action may carry `"duration": "<ISO 8601>"` (e.g.
`"PT5M"`); actions without one default to `"PT0S"`. Every `plan` response
includes a `"temporal"` block computed from these durations, with no separate
call needed.

A plan is a temporal plan, and its steps are **scheduled, not merely listed**.
Each step is a transaction over the plan's state, and the schedule is what
FoundationDB calls **strict serializability**: the intervals the block reports
"could have been produced by executing transactions one at a time, even though
they may actually have been executed concurrently"
([Conflict ranges](https://apple.github.io/foundationdb/developer-guide.html#conflict-ranges)).

A step's **conflict ranges** come from its body. Its write conflict range is the
state pointers it writes; its read conflict range is the ones it reads. Two steps
conflict when one writes a pointer the other writes or reads — FoundationDB
states the same test as "the first to commit writes a value that the second
reads". A step that writes nothing takes no write conflict range, and read-only
transactions "never conflict", so a read against a read is not a conflict.

The engine also adds a conflict range for each ReBAC endpoint pair a step's
guards name, so two steps that use the same capability do not overlap.
FoundationDB offers exactly this lever — "conflicts can be *created*, increasing
isolation, by explicitly adding read or write conflict ranges" — and reaches for
it for the same reason in its own guarded-increment example. A step holds the
capability it checks for its whole duration, so the pair is added as a write
conflict range.

Steps whose conflict ranges do not intersect run side by side, so
`temporal.total` is the makespan rather than the sum of the durations.

`consistent` is false iff the reported intervals cannot be ordered so that every
conflicting pair is in conflict-range order — that is, iff a step overlaps an
earlier step it is not allowed to overlap.

Two calls of one parameterised action on two agents write `/loc/drone_1` and
`/loc/drone_2`, so they run together and the plan costs one duration:

```json
{"plan": [["a_fly", "drone_1", "city"], ["a_fly", "drone_2", "city"]],
 "temporal": {"consistent": true, "origin": "PT0S", "total": "PT5M",
              "steps": [{"action": "a_fly", "duration": "PT5M", "start": "PT0S", "end": "PT5M"},
                        {"action": "a_fly", "duration": "PT5M", "start": "PT0S", "end": "PT5M"}]}}
```

The same two calls on one agent both write `/loc/drone_1`, so the second waits
for the first and the plan costs both:

```json
{"plan": [["a_fly", "drone_1", "city"], ["a_fly", "drone_1", "harbor"]],
 "temporal": {"consistent": true, "origin": "PT0S", "total": "PT10M",
              "steps": [{"action": "a_fly", "duration": "PT5M", "start": "PT0S", "end": "PT5M"},
                        {"action": "a_fly", "duration": "PT5M", "start": "PT5M", "end": "PT10M"}]}}
```

`test/temporal_concurrency_test.exs` in
`V-Sekai-fire/interactor-rectgtn-domain-c-abi` measures both rows, and pairs
every independent case with its contending twin.

## Soundness contract

`Taskweft.replan/3` takes the plan **array**, not the envelope `Taskweft.plan/1`
returns. Passing the envelope is accepted and answers `original_plan` of `[]`
with `completed_steps` of `0`, so it reads as a complete replan without being
one.

The envelope carries `fail_step`, `completed_steps`, `original_plan`, `new_plan`
and `recovered`. `Taskweft.NIF.plan/1` is the raw binding and answers the array
alone; `Taskweft.plan/1` wraps that array with the `temporal` block.

### `fail_step == -1` — the whole plan ran

Replanning a returned plan with `fail_step == -1` reports the whole plan
complete:

```elixir
{:ok, plan_json} = Taskweft.plan(domain_json)   # {"plan": [...], "temporal": {...}}
plan = Jason.decode!(plan_json)["plan"]
{:ok, out} = Taskweft.replan(domain_json, Jason.encode!(plan), -1)
env = Jason.decode!(out)
env["fail_step"]       == -1
env["completed_steps"] == length(plan)
```

Nothing is blacklisted, and `new_plan` is the plan that was passed in. A
`fail_step` at or past the end of the plan is this case.

### `fail_step >= 0` — the plan failed at that step

`fail_step` is the 0-based index of the action that failed at runtime. The
contract is **replay the prefix, blacklist the failed command, re-solve the
original task list**. It is not a local repair of the failed subtask, and it is
not a rollback of state mutations through pointer history.

1. **Replay.** The first `fail_step` actions are re-applied, in order, to a
   copy of the initial state, and `completed_steps` is `fail_step`. The state
   is rebuilt from the domain and the plan array rather than restored from a
   history, so a plan whose actions are not deterministic replays to whatever
   those actions do now.
2. **Blacklist.** The *command* at `fail_step` — that exact `(action, args)`
   instantiation, not the action name — is blacklisted for the search, so the
   planner cannot re-select it and must find another decomposition. A sibling
   command of the same action stays available.
3. **Re-solve.** The planner searches the **original task list** again, from
   the replayed state. The answer is a whole plan from that state, so an
   alternative that repeats the prefix repeats it in `new_plan`; `new_plan` is
   not a suffix to splice onto the steps that already ran.
4. **Refusal.** When no alternative decomposition exists, `new_plan` is `null`
   and `recovered` is `false`, with `completed_steps` still `fail_step`.

In the domain below both of `top`'s alternatives start with `do_a`, so a
failure at step 0 has nothing else to try. `plan` is `[["do_a"],["do_b"]]`.

```json
{"@type": "domain:Definition", "name": "replan_example",
 "variables": [{"name": "done", "type": "bool", "init": {"a": false, "b": false}}],
 "actions": {"do_a": {"params": [], "body": [{"pointer/set": "/done/a", "value": true}]},
             "do_b": {"params": [], "body": [{"pointer/set": "/done/b", "value": true}]},
             "do_c": {"params": [], "body": [{"pointer/set": "/done/b", "value": true}]}},
 "methods": {"top": {"params": [], "alternatives": [
   {"name": "alt_ab", "subtasks": [["do_a"], ["do_b"]]},
   {"name": "alt_ac", "subtasks": [["do_a"], ["do_c"]]}]}},
 "todo_list": [["top"]]}
```

| `fail_step` | `completed_steps` | `recovered` | `new_plan` |
|---|---|---|---|
| `-1` | `2` | `true` | `[["do_a"],["do_b"]]` |
| `0` | `0` | `false` | `null` |
| `1` | `1` | `true` | `[["do_a"],["do_c"]]` |
| `5` | `2` | `true` | `[["do_a"],["do_b"]]` |

`test/taskweft/replan_contract_test.exs` runs every row of that table against
the planner and fails on any difference, so the table is measured rather than
asserted. It carries two further domains that discriminate the claims above:
one whose second alternative applies only once the prefix has run, so a
rollback to the initial state would refuse where the replay recovers, and one
whose action is parameterised, so blacklisting the action name would refuse
where blacklisting the command recovers.

## Composing several documents

`Taskweft.Compose.compose/1` folds a list of documents into one, left
to right. `Taskweft.Compose.compose_strings/2` does the same for source
strings, in either format.

A pipeline that runs several models is several domains. Each one owns
its own actions and its own guards, and each one reads alone. Compose
them and the planner sees one document. The alternative is one large
domain per pipeline, and two pipelines that share a stage then keep two
copies of it.

Later documents win, so the fold order carries meaning:

| Field | Rule |
|-------|------|
| `variables` | Merge by `name`. `init` unions its keys, and the later one wins a shared key. |
| `actions` | Merge by key. The later one replaces. |
| `methods` | Merge by key. The later one replaces. |
| `enums` | Merge by key. The later one replaces. |
| `capabilities.graph.edges` | Concatenate. |
| `capabilities.graph.definitions` | Merge by key. The later one replaces. |
| `todo_list` | A non-empty list replaces. An empty one keeps. |
| everything else | The first document's value stands. |

A problem is an ordinary document under these rules, thus
`compose([domain, problem])` gives what `--problem` gives. The CLI takes
that path now, and it holds no rules of its own.

Over MCP, the `overlays` parameter on `plan` and on `validate` takes the
documents to compose over `domain_dsl`:

```json
{"domain_dsl": "<base domain>",
 "overlays": ["<stage domain>", "<problem>"],
 "format": "dsl"}
```

## See also

- [ADR 0001](https://github.com/V-Sekai-fire/interactor-taskweft/blob/main/docs/adr/0001-gltf-interactivity-node-shape.md) — the action-body node shape (`eval` + `pointer/set`).
- [ADR 0002](https://github.com/V-Sekai-fire/interactor-taskweft/blob/main/docs/adr/0002-khr-interactivity-tier1-node-conventions.md) — the glTF Interactivity node catalog conventions.
- [ADR 0003](https://github.com/V-Sekai-fire/interactor-taskweft/blob/main/docs/adr/0003-khr-interactivity-tier2-execution-strategy.md) — the planned flow-graph execution engine.
- [ADR 0004](https://github.com/V-Sekai-fire/interactor-taskweft/blob/main/docs/adr/0004-unify-domain-capabilities-with-rebac-graph.md) — unifying domain capabilities with the ReBAC relation-expression engine (issue #96).
