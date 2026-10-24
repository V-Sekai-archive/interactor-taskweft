# interactor-taskweft

A general hierarchical task network planner over RECTGTN, served as plan and validate tools over the Model Context Protocol.

## What it is for

It plans over RECTGTN, the Relationship-Enabled Capability-Temporal Goal-Task-Network model described in [docs/rectgtn.md](docs/rectgtn.md). Domains are written in an Elixir DSL or in JSON-LD. RFD66606-2304 in [manuals-weftspun](https://github.com/V-Sekai-fire/manuals-weftspun) owns the planner's design.

## Build and run

```sh
mix deps.get
mix taskweft.mcp
```

Prebuilt `taskweft` binaries are attached to the [releases](https://github.com/V-Sekai-fire/interactor-taskweft/releases), and `taskweft help` lists their commands.

## Licence

MIT; see LICENSE.

<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->
