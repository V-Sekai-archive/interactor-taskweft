# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.CapabilitiesShapeTest do
  @moduledoc """
  Holds `capabilities` to one representation: `graph`.

  `capabilities.entities` was sugar that compiled into `HAS_CAPABILITY` edges,
  while action requirements had no sugar at all — the same section of the spec
  allowed a shortcut on one axis and forbade it on the other (issue #5). The
  schema is the authority: `capabilities` is a closed set, so a key it does not
  list is not a key a document may carry.

  Three directions are checked. The schema's set, the spec's example, and the
  loader's answer must agree, so neither a re-added schema key nor a re-added
  spec line passes. The controls plant the removed key in the schema and in the
  spec, and reword the spec anchor.
  """

  use ExUnit.Case, async: true

  alias Taskweft.JSONLD.Loader

  @schema_path "priv/schemas/rectgtn_domain.schema.json"
  @doc_path "docs/rectgtn.md"

  @shape_files [
    "docs/rectgtn.md",
    "lib/taskweft/compose.ex",
    "lib/taskweft/cli.ex",
    "lib/taskweft/mcp/server.ex",
    "lib/taskweft/dsl/safe_parser.ex",
    "priv/plans/domains/meta_loader.jsonld",
    "priv/plans/domains/meta_loader_dsl.ex"
  ]

  describe "capabilities has one representation" do
    test "the schema allows graph and nothing else" do
      assert {:ok, ["graph"]} = schema_keys(schema())
    end

    test "the schema closes the set, so an unlisted key is refused" do
      assert capabilities(schema())["additionalProperties"] == false
    end

    test "the spec's example names exactly the schema's keys" do
      assert {:ok, ["graph"]} = schema_keys(schema())
      assert {:ok, doc_keys} = doc_keys(doc())
      assert doc_keys == ["graph"]
    end

    test "no file in the tree still names capabilities.entities" do
      named =
        Enum.filter(@shape_files, &String.contains?(File.read!(&1), "capabilities.entities"))

      assert named == []
    end

    test "the loader refuses the entities sugar" do
      doc =
        base(%{"capabilities" => %{"entities" => %{"drone_1" => ["fly"]}}})

      assert {:error, msg} = Loader.validate(doc, %{})
      assert msg =~ "#/capabilities/entities"
    end

    test "the loader accepts a graph carrying the same edge" do
      doc =
        base(%{
          "capabilities" => %{
            "graph" => %{
              "edges" => [
                %{"subject" => "drone_1", "rel" => "HAS_CAPABILITY", "object" => "fly"}
              ],
              "definitions" => %{}
            }
          }
        })

      assert :ok = Loader.validate(doc, %{})
    end
  end

  describe "controls" do
    test "control: the removed key planted in the schema is reported" do
      drifted =
        plant(
          schema(),
          ~s|"graph": { "$ref": "#/$defs/rebac_graph" }|,
          ~s|"entities": { "type": "object" },\n        "graph": { "$ref": "#/$defs/rebac_graph" }|
        )

      assert {:ok, keys} = schema_keys(drifted)
      assert keys == ["entities", "graph"]
    end

    test "control: the removed key planted in the spec example is reported" do
      drifted =
        plant(
          doc(),
          ~s|"capabilities": {\n|,
          ~s|"capabilities": {\n  "entities": {"<entity>": ["<cap>"]},\n|
        )

      assert {:ok, keys} = doc_keys(drifted)
      assert keys == ["entities", "graph"]
    end

    test "control: a reworded spec anchor is an error, not an empty pass" do
      drifted = plant(doc(), ~s|"capabilities": {|, ~s|"capability": {|)
      assert {:error, :capabilities_example_not_found} = doc_keys(drifted)
    end

    test "control: a closed set that was opened is reported" do
      drifted =
        plant(
          schema(),
          ~s|"additionalProperties": false,\n      "description": "ReBAC|,
          ~s|"description": "ReBAC|
        )

      refute capabilities(drifted)["additionalProperties"] == false
    end
  end

  defp base(extra),
    do: Map.merge(%{"@type" => "domain:Problem", "name" => "t"}, extra)

  defp schema_json(text), do: Jason.decode!(text)
  defp capabilities(text), do: schema_json(text)["properties"]["capabilities"]

  defp schema_keys(text) do
    case capabilities(text)["properties"] do
      properties when is_map(properties) -> {:ok, Map.keys(properties)}
      _other -> {:error, :capabilities_properties_not_found}
    end
  end

  # The top-level keys of the spec's `"capabilities": {...}` example: the lines
  # between the opening brace and the closing brace in the first column.
  defp doc_keys(text) do
    lines = String.split(text, "\n")

    case Enum.find_index(lines, &Regex.match?(~r/^\s*"capabilities":\s*\{\s*$/, &1)) do
      nil ->
        {:error, :capabilities_example_not_found}

      anchor ->
        keys =
          lines
          |> Enum.drop(anchor + 1)
          |> Enum.take_while(&(not Regex.match?(~r/^\}/, &1)))
          |> Enum.flat_map(fn line ->
            case Regex.run(~r/^\s{2}"([a-z_]+)":/, line) do
              [_, key] -> [key]
              nil -> []
            end
          end)

        {:ok, keys}
    end
  end

  # A control asserts its own plant landed: a replacement that no longer
  # matches would otherwise leave the control passing on unmodified input.
  defp plant(text, from, to) do
    drifted = String.replace(text, from, to)
    assert drifted != text, "control did not apply: #{inspect(from)} not found"
    drifted
  end

  defp schema, do: File.read!(@schema_path)
  defp doc, do: File.read!(@doc_path)
end
