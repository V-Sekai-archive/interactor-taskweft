# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule MetaLoader do
  use Taskweft.DSL

  @name "meta_loader"
  @description "The domain loader expressed as a domain. Homoiconic: the loader uses the same bind/check/set vocabulary it interprets. Each action below corresponds to a loader operation on the planner registry. This meta-domain demonstrates homoiconicity: the loader that interprets bind/check/set is itself described using bind/check/set. The three primitives (exec_bind = variable/get, exec_check = variable/get + math/ieq + flow/branch, exec_set = variable/set) are the complete standard library for state manipulation in KHR_interactivity."

  @actions %{{
    resolve_val: %{
      # Resolve a {param} template as a value through enum lookup. Maps to variable/get + math/select.
      params: [:template, :bindings, :enums],
      body: [
        %{name: "raw", from: ["bindings", "{template}"]}
      ],
    },
  }

  @actions %{{
    resolve_key: %{
      # Resolve a {param} template as a dict key (no enum). Maps to variable/get.
      params: [:template, :bindings],
      body: [
        %{name: "raw", from: ["bindings", "{template}"]}
      ],
    },
  }

  @actions %{{
    exec_bind: %{
      # variable/get: read state[var][key] and store in bindings[name].
      params: [:var, :key, :name],
      body: [
        %{name: "val", from: ["{var}", "{key}"]}
      ],
    },
  }

  @actions %{{
    exec_check: %{
      # variable/get + math/ieq: read state[var][key], compare to expected. Fail (return None) on mismatch. Maps to flow/branch(false → fail).
      params: [:var, :key, :expected],
      body: [
      ],
    },
  }

  @actions %{{
    exec_set: %{
      # variable/set: write state[var][key] = value.
      params: [:var, :key, :value],
      body: [
      ],
    },
  }

  @actions %{{
    register_action: %{
      # Create an IPyHOP action from a sequence of bind/check/set steps. The action body is data — each step is one of the three primitives above.
      params: [:name, :params, :bind_steps, :body_steps, :enums],
    },
  }

  @actions %{{
    register_method: %{
      # Create an IPyHOP task method from alternatives. Each alternative is a sequence of bind/check steps followed by a subtask list.
      params: [:task_name, :params, :alternatives],
    },
  }

  @actions %{{
    register_goal_method: %{
      # Create an IPyHOP goal method. Same as register_method but registered via declare_goal_methods for unigoal verification (RECTGTN C).
      params: [:goal_name, :params, :alternatives],
    },
  }

  @actions %{{
    register_multigoal_method: %{
      # Create an IPyHOP multigoal method. Decomposes a conjunction of unigoals one at a time (RECTGTN N).
      params: [:tag],
    },
  }

  @actions %{{
    register_capabilities: %{
      # Register the domain's ReBAC relationship graph (ADR 0004) — the single
      # canonical representation of capabilities.
      params: [:graph],
    },
  }

  @actions %{{
    init_state: %{
      # Create IPyHOP State from variable definitions.
      params: [:name, :variables],
    },
  }

end