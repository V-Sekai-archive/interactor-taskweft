# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee
defmodule Taskweft.SpecRelationsTest do
  @moduledoc """
  Keeps the spec's relation list equal to the model's enum.

  `docs/rectgtn.md` names the core ReBAC relations and `lean/Planner/Types.lean`
  defines them; the two drifted once — the doc listed `CAN_ENTER` and
  `CAN_INSTANCE` as built-ins while the `RelationType` enum carries `IS_A` and
  neither of them. This test reads both files and fails on any difference, so
  the next drift is caught by CI rather than by a reader.

  The four control tests plant the drift the gate exists to catch, a rewording
  that hides the sentence, and a renamed enum, so a broken extractor cannot
  read as a pass.
  """

  use ExUnit.Case, async: true

  @doc_path "docs/rectgtn.md"
  @lean_path "lean/Planner/Types.lean"

  describe "spec relations" do
    test "the spec's list is the model's enum" do
      {:ok, doc_rels} = doc_relations(doc())
      {:ok, lean_rels} = lean_relations(lean())

      assert length(doc_rels) == 8
      assert Enum.sort(doc_rels) == Enum.sort(lean_rels)
    end

    test "control: a relation the enum lacks is reported" do
      drifted = String.replace(doc(), "`IS_A`.", "`IS_A`, `CAN_ENTER`.")
      assert drift(drifted, lean()) == {:ok, ["CAN_ENTER"], []}
    end

    test "control: a relation the spec lacks is reported" do
      drifted = String.replace(doc(), "`PARTNER_OF`, ", "")
      assert drift(drifted, lean()) == {:ok, [], ["PARTNER_OF"]}
    end

    test "control: a reworded spec sentence is a failure, not a skip" do
      assert drift(String.replace(doc(), "Relations are", "Edges are"), lean()) ==
               {:error, :spec_sentence_not_found}
    end

    test "control: a renamed enum is a failure, not a skip" do
      assert drift(doc(), String.replace(lean(), "RelationType", "RelationKind")) ==
               {:error, :lean_enum_not_found}
    end
  end

  defp drift(doc_text, lean_text) do
    with {:ok, doc_rels} <- doc_relations(doc_text),
         {:ok, lean_rels} <- lean_relations(lean_text) do
      {:ok, Enum.sort(doc_rels -- lean_rels), Enum.sort(lean_rels -- doc_rels)}
    end
  end

  # The sentence starts at "Relations are" and ends at its first period that is
  # followed by whitespace, so the periods in `Planner/Types.lean` do not end it.
  defp doc_relations(text) do
    case Regex.run(~r/Relations are .*?\.(?=\s|$)/s, text) do
      [sentence | _] -> relation_names(sentence, :spec_sentence_not_found)
      nil -> {:error, :spec_sentence_not_found}
    end
  end

  defp lean_relations(text) do
    case Regex.run(~r/inductive RelationType where\n(.*?)\n\s*deriving/s, text) do
      [_, body] -> relation_names(body, :lean_enum_not_found)
      nil -> {:error, :lean_enum_not_found}
    end
  end

  defp relation_names(text, on_empty) do
    names =
      ~r/`([A-Z][A-Z_]+)`|^\s*\|\s*([A-Z][A-Z_]*)\s*$/m
      |> Regex.scan(text)
      |> Enum.map(fn
        [_, backticked, ""] -> backticked
        [_, backticked] -> backticked
        [_, "", constructor] -> constructor
      end)
      |> Enum.uniq()

    if names == [], do: {:error, on_empty}, else: {:ok, names}
  end

  defp doc, do: File.read!(@doc_path)
  defp lean, do: File.read!(@lean_path)
end
