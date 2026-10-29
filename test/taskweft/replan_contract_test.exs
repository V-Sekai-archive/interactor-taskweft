# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.ReplanContractTest do
  @moduledoc """
  Measures the `fail_step` contract `docs/rectgtn.md` §Soundness contract states.

  The spec defined only `fail_step == -1`; what `fail_step >= 0` does was
  implied by the C-ABI and written down nowhere. It is a replay of the plan
  prefix onto a copy of the initial state, a blacklist of the failed
  *command*, and a fresh search over the original task list — not a local
  task repair and not a pointer-history rollback.

  The worked example in the spec is the fixture here: every row of its table is
  run against the planner and compared, so the table is measured rather than
  asserted. Two further domains discriminate the claims a reader would
  otherwise have to take on trust — one where a rollback to the initial state
  would refuse rather than recover, and one where blacklisting the action name
  rather than the command would refuse.
  """

  use ExUnit.Case, async: true

  @doc_path "docs/rectgtn.md"

  # `top` has two alternatives and both start with `do_a`, so a failure at step
  # 0 has no alternative decomposition to find and the replan refuses.
  @example %{
    "@context" => %{
      "khr" => "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
      "domain" => "khr:planning/domain/"
    },
    "@type" => "domain:Definition",
    "name" => "replan_example",
    "variables" => [
      %{"name" => "done", "type" => "bool", "init" => %{"a" => false, "b" => false}}
    ],
    "actions" => %{
      "do_a" => %{"params" => [], "body" => [%{"pointer/set" => "/done/a", "value" => true}]},
      "do_b" => %{"params" => [], "body" => [%{"pointer/set" => "/done/b", "value" => true}]},
      "do_c" => %{"params" => [], "body" => [%{"pointer/set" => "/done/b", "value" => true}]}
    },
    "methods" => %{
      "top" => %{
        "params" => [],
        "alternatives" => [
          %{"name" => "alt_ab", "subtasks" => [["do_a"], ["do_b"]]},
          %{"name" => "alt_ac", "subtasks" => [["do_a"], ["do_c"]]}
        ]
      }
    },
    "todo_list" => [["top"]]
  }

  # The second alternative applies only once `do_a` has run. Replanning from a
  # rolled-back initial state would refuse; replanning from the replayed prefix
  # recovers.
  @guarded %{
    "@context" => %{
      "khr" => "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
      "domain" => "khr:planning/domain/"
    },
    "@type" => "domain:Definition",
    "name" => "replan_guarded",
    "variables" => [
      %{"name" => "done", "type" => "bool", "init" => %{"a" => false, "b" => false}}
    ],
    "actions" => %{
      "do_a" => %{"params" => [], "body" => [%{"pointer/set" => "/done/a", "value" => true}]},
      "do_b" => %{"params" => [], "body" => [%{"pointer/set" => "/done/b", "value" => true}]},
      "do_c" => %{"params" => [], "body" => [%{"pointer/set" => "/done/b", "value" => true}]}
    },
    "methods" => %{
      "top" => %{
        "params" => [],
        "alternatives" => [
          %{"name" => "alt_ab", "subtasks" => [["do_a"], ["do_b"]]},
          %{
            "name" => "alt_c_after_a",
            "check" => [
              %{
                "eval" => %{
                  "type" => "math/eq",
                  "a" => %{"type" => "pointer/get", "pointer" => "/done/a"},
                  "b" => true
                }
              }
            ],
            "subtasks" => [["do_c"]]
          }
        ]
      }
    },
    "todo_list" => [["top"]]
  }

  # The one action is parameterised, and the second alternative paints `b`
  # alone. Blacklisting `paint` by name would refuse; blacklisting the failed
  # command `paint(a)` recovers.
  @commands %{
    "@context" => %{
      "khr" => "https://registry.khronos.org/glTF/extensions/2.0/KHR_interactivity/",
      "domain" => "khr:planning/domain/"
    },
    "@type" => "domain:Definition",
    "name" => "replan_commands",
    "variables" => [
      %{"name" => "painted", "type" => "bool", "init" => %{"a" => false, "b" => false}}
    ],
    "actions" => %{
      "paint" => %{
        "params" => ["item"],
        "body" => [%{"pointer/set" => "/painted/{item}", "value" => true}]
      }
    },
    "methods" => %{
      "two" => %{
        "params" => [],
        "alternatives" => [
          %{"name" => "both", "subtasks" => [["paint", "a"], ["paint", "b"]]},
          %{"name" => "just_b", "subtasks" => [["paint", "b"]]}
        ]
      }
    },
    "todo_list" => [["two"]]
  }

  describe "the spec's worked example is measured" do
    test "every row of the table is what the planner answers" do
      assert {:ok, rows} = contract_rows(doc())
      plan = plan_of(@example)

      assert rows != []

      for %{fail_step: fail_step} = row <- rows do
        assert row == measure(@example, plan, fail_step),
               "docs/rectgtn.md row for fail_step #{fail_step} is not what replan/3 answers"
      end
    end

    test "the table covers the four cases the contract names" do
      assert {:ok, rows} = contract_rows(doc())
      assert Enum.map(rows, & &1.fail_step) == [-1, 0, 1, 5]
    end
  end

  describe "the prefix is replayed, not rolled back" do
    test "a failure at step 1 recovers from the state the prefix reached" do
      plan = plan_of(@guarded)
      assert plan == [["do_a"], ["do_b"]]

      env = measure(@guarded, plan, 1)

      # `alt_c_after_a` requires `/done/a`, which only the replayed prefix sets.
      assert env.completed_steps == 1
      assert env.new_plan == [["do_c"]]
      assert env.recovered == true
    end

    test "control: the same domain with no prefix replayed refuses" do
      plan = plan_of(@guarded)
      env = measure(@guarded, plan, 0)

      assert env.completed_steps == 0
      assert env.new_plan == nil
      assert env.recovered == false
    end
  end

  describe "the blacklist is the command, not the action" do
    test "a failed paint(a) leaves paint(b) available" do
      plan = plan_of(@commands)
      assert plan == [["paint", "a"], ["paint", "b"]]

      env = measure(@commands, plan, 0)

      assert env.completed_steps == 0
      assert env.new_plan == [["paint", "b"]]
      assert env.recovered == true
    end
  end

  describe "controls" do
    test "control: a mutated cell in the table is reported" do
      drifted =
        plant(doc(), "| `0` | `0` | `false` | `null` |", "| `0` | `1` | `false` | `null` |")

      assert {:ok, rows} = contract_rows(drifted)
      plan = plan_of(@example)

      refute Enum.all?(rows, &(&1 == measure(@example, plan, &1.fail_step)))
    end

    test "control: a missing row is reported" do
      drifted = plant(doc(), "| `1` | `1` | `true` | `[[\"do_a\"],[\"do_c\"]]` |\n", "")
      assert {:ok, rows} = contract_rows(drifted)
      assert Enum.map(rows, & &1.fail_step) == [-1, 0, 5]
    end

    test "control: a reworded table header is an error, not an empty pass" do
      drifted =
        plant(doc(), "| `fail_step` | `completed_steps` |", "| `step` | `completed_steps` |")

      assert {:error, :contract_table_not_found} = contract_rows(drifted)
    end
  end

  defp plan_of(domain), do: domain |> Jason.encode!() |> plan_from()

  defp plan_from(domain_json) do
    {:ok, plan_json} = Taskweft.plan(domain_json)
    Jason.decode!(plan_json)["plan"]
  end

  defp measure(domain, plan, fail_step) do
    {:ok, out} = Taskweft.replan(Jason.encode!(domain), Jason.encode!(plan), fail_step)
    env = Jason.decode!(out)

    %{
      fail_step: env["fail_step"],
      completed_steps: env["completed_steps"],
      recovered: env["recovered"],
      new_plan: env["new_plan"]
    }
  end

  # The table under the anchor, read as rows of measured values. A reworded
  # anchor is an error: an empty extraction would compare equal to nothing.
  defp contract_rows(text) do
    lines = String.split(text, "\n")

    anchor =
      Enum.find_index(
        lines,
        &Regex.match?(~r/^\|\s*`fail_step`\s*\|\s*`completed_steps`\s*\|/, &1)
      )

    case anchor do
      nil ->
        {:error, :contract_table_not_found}

      header ->
        rows =
          lines
          |> Enum.drop(header + 2)
          |> Enum.take_while(&Regex.match?(~r/^\s*\|/, &1))
          |> Enum.map(&row/1)
          |> Enum.reject(&is_nil/1)

        {:ok, rows}
    end
  end

  defp row(line) do
    cells = line |> String.split("|") |> Enum.map(&String.trim/1)

    case cells |> Enum.drop(1) |> Enum.drop(-1) do
      [fail_step, completed_steps, recovered, new_plan] ->
        %{
          fail_step: cell_integer(fail_step),
          completed_steps: cell_integer(completed_steps),
          recovered: unbacktick(recovered) == "true",
          new_plan: Jason.decode!(unbacktick(new_plan))
        }

      _other ->
        nil
    end
  end

  defp cell_integer(cell), do: cell |> unbacktick() |> String.to_integer()
  defp unbacktick(cell), do: String.trim(cell, "`")

  # A control asserts its own plant landed: a replacement that no longer
  # matches would otherwise leave the control passing on unmodified input.
  defp plant(text, from, to) do
    drifted = String.replace(text, from, to)
    assert drifted != text, "control did not apply: #{inspect(from)} not found"
    drifted
  end

  defp doc, do: File.read!(@doc_path)
end
