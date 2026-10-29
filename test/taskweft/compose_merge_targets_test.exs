# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.ComposeMergeTargetsTest do
  @moduledoc """
  Keeps the Compose merge targets equal to the schema's top-level fields.

  `priv/schemas/rectgtn_domain.schema.json` is the authoritative shape, with
  `additionalProperties: false` at the top level — a key it does not list is
  not a key a document may carry. The Compose moduledoc table, the
  `docs/rectgtn.md` Compose table and `@merge_by_key` all named
  `goal_methods`, which the schema lacks: phantom surface, because a goal
  method is mechanically an ordinary `methods` entry (docs/rectgtn.md
  §TwGoal). This test reads the schema, both tables and the code list, and
  fails on any difference, so the next drift is caught by CI.

  The controls plant the drift this gate exists to catch — the removed row, in
  each of the three places it lived — plus a reworded table header and a
  dropped code entry, so a broken extractor cannot read as a pass.
  """

  use ExUnit.Case, async: true

  @schema_path "priv/schemas/rectgtn_domain.schema.json"
  @compose_path "lib/taskweft/compose.ex"
  @doc_path "docs/rectgtn.md"

  describe "compose merge targets" do
    test "every merge target named in code or either table is a schema field" do
      assert {:ok, []} = phantom_targets(schema(), compose(), doc())
    end

    test "the two tables list the same fields" do
      assert {:ok, compose_fields} = table_fields(compose())
      assert {:ok, doc_fields} = table_fields(doc())

      assert Enum.sort(compose_fields) == Enum.sort(doc_fields)
    end

    test "every @merge_by_key entry is a documented row in both tables" do
      assert {:ok, code} = code_merge_by_key(compose())
      assert {:ok, compose_fields} = table_fields(compose())
      assert {:ok, doc_fields} = table_fields(doc())

      assert Enum.sort(code -- compose_fields) == []
      assert Enum.sort(code -- doc_fields) == []
    end

    test "the schema does not carry goal_methods" do
      refute "goal_methods" in Map.keys(schema_json()["properties"])
    end
  end

  describe "controls" do
    test "control: the removed row is reported from the docs table" do
      drifted = plant(doc(), "| `methods` |", "| `goal_methods` | Merge by key. |\n| `methods` |")
      assert {:ok, ["goal_methods"]} = phantom_targets(schema(), compose(), drifted)
    end

    test "control: the removed row is reported from the moduledoc table" do
      drifted =
        plant(
          compose(),
          "  | `methods` |",
          "  | `goal_methods` | Merge by key. |\n  | `methods` |"
        )

      assert {:ok, ["goal_methods"]} = phantom_targets(schema(), drifted, doc())
    end

    test "control: the removed row is reported from @merge_by_key" do
      drifted =
        plant(compose(), ~s|["methods", "actions"]|, ~s|["methods", "actions", "goal_methods"]|)

      assert {:ok, ["goal_methods"]} = phantom_targets(schema(), drifted, doc())
    end

    test "control: a reworded docs table header is a failure, not a skip" do
      drifted = plant(doc(), "| Field | Rule |", "| Key | Rule |")
      assert {:error, :table_not_found} = phantom_targets(schema(), compose(), drifted)
    end

    test "control: a reworded moduledoc table header is a failure, not a skip" do
      drifted = plant(compose(), "| Field | Rule |", "| Key | Rule |")
      assert {:error, :table_not_found} = phantom_targets(schema(), drifted, doc())
    end

    test "control: a code entry with no table row is reported" do
      drifted =
        plant(compose(), ~s|["methods", "actions"]|, ~s|["methods", "actions", "version"]|)

      assert {:ok, code} = code_merge_by_key(drifted)
      assert {:ok, doc_fields} = table_fields(doc())

      assert code -- doc_fields == ["version"]
    end

    test "control: an unknown schema field is reported" do
      drifted = plant(doc(), "| `methods` |", "| `goal_methodz` | Merge by key. |\n| `methods` |")
      assert {:ok, ["goal_methodz"]} = phantom_targets(schema(), compose(), drifted)
    end
  end

  # A control asserts its own plant landed: a replacement that no longer
  # matches would otherwise leave the control passing on unmodified input.
  defp plant(text, from, to) do
    drifted = String.replace(text, from, to)
    assert drifted != text, "control did not apply: #{inspect(from)} not found"
    drifted
  end

  # Merge targets named by the code list or by either table that the schema
  # does not define.
  defp phantom_targets(schema_text, compose_text, doc_text) do
    with {:ok, code} <- code_merge_by_key(compose_text),
         {:ok, compose_fields} <- table_fields(compose_text),
         {:ok, doc_fields} <- table_fields(doc_text) do
      named = Enum.uniq(code ++ compose_fields ++ doc_fields)
      {:ok, Enum.reject(named, &resolves?(schema_text, &1))}
    end
  end

  # A dotted name is a path through the schema, following `$ref` into `$defs`,
  # so `capabilities.graph.edges` is checked segment by segment rather than by
  # its first word alone.
  defp resolves?(schema_text, name) do
    case Jason.decode(schema_text) do
      {:ok, schema} ->
        name
        |> String.split(".")
        |> Enum.reduce_while({:ok, schema}, fn segment, {:ok, node} ->
          case deref(schema, node) do
            %{"properties" => properties} when is_map(properties) ->
              case Map.fetch(properties, segment) do
                {:ok, child} -> {:cont, {:ok, child}}
                :error -> {:halt, :error}
              end

            _other ->
              {:halt, :error}
          end
        end)
        |> case do
          {:ok, _node} -> true
          :error -> false
        end

      {:error, _reason} ->
        false
    end
  end

  defp deref(schema, %{"$ref" => "#/$defs/" <> definition}),
    do: get_in(schema, ["$defs", definition]) || %{}

  defp deref(_schema, node), do: node

  defp code_merge_by_key(text) do
    case Regex.run(~r/@merge_by_key\s*\[(.*?)\]/s, text) do
      [_, body] -> {:ok, Regex.scan(~r/"([^"]+)"/, body) |> Enum.map(fn [_, name] -> name end)}
      nil -> {:error, :merge_by_key_not_found}
    end
  end

  # The field rows of the moduledoc / spec Compose table. The header is the
  # anchor: a reworded one is an error, never an empty extraction that compares
  # equal to nothing.
  defp table_fields(text) do
    lines = String.split(text, "\n")

    case Enum.find_index(lines, &Regex.match?(~r/^\s*\|\s*Field\s*\|\s*Rule\s*\|\s*$/, &1)) do
      nil ->
        {:error, :table_not_found}

      header ->
        fields =
          lines
          |> Enum.drop(header + 1)
          |> Enum.take_while(&Regex.match?(~r/^\s*\|/, &1))
          |> Enum.flat_map(fn row ->
            case Regex.run(~r/^\s*\|\s*`([a-z_][a-z0-9_.]*)`\s*\|/, row) do
              [_, name] -> [name]
              nil -> []
            end
          end)

        {:ok, fields}
    end
  end

  defp schema_json, do: Jason.decode!(schema())
  defp schema, do: File.read!(@schema_path)
  defp compose, do: File.read!(@compose_path)
  defp doc, do: File.read!(@doc_path)
end
