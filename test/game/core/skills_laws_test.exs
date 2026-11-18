defmodule ThistleTea.Game.Core.SkillsLawsTest do
  use ExUnit.Case, async: true
  use Lynx.Case

  alias ThistleTea.Game.Core.Skills

  def proper_list?([]), do: true
  def proper_list?([_ | rest]), do: proper_list?(rest)
  def proper_list?(_), do: false

  def lookup_after_forgetting(active, archive, ids, id) do
    {active, archive} = Skills.forget(active, ids, archive)
    {Map.fetch(active, id), Map.fetch(archive, id)}
  end

  def expected_progress(active, archive, ids, id) do
    known = Map.fetch(active, id)
    stored = Map.fetch(archive, id)

    case {:lists.member(id, ids), known} do
      {false, _} -> {known, stored}
      {true, :error} -> {:error, stored}
      {true, progress} -> {:error, progress}
    end
  end

  laws "Skills.forget/3" do
    cutoff &IO.warn/1
    cutoff &Enum.to_list/1
    termination_suffix &Map.drop/2, ~LEAN"partial_fixpoint"
    termination_suffix &Map.take/2, ~LEAN"partial_fixpoint"

    postlude "skills_forget.lean"

    law forgetting_preserves_progress(active, archive, ids, id),
      requires: is_map(active) and is_map(archive) and proper_list?(ids),
      expects: lookup_after_forgetting(active, archive, ids, id) === expected_progress(active, archive, ids, id),
      proof: ~LEAN"""
      open Lynx Elixir.ThistleTea.Game.Core in
        unfold «forgetting_preserves_progress:requires/4» at requires
        cases active <;> simp [Erlang.erlang.«is_map/1»] at requires
        cases archive <;> simp at requires
        rename_i active archive
        obtain ⟨ids, rfl⟩ := list_of_proper ids requires
        obtain ⟨kept, drop, kept_lookup⟩ := drop_lookup ids active id
        obtain ⟨taken, take, taken_lookup⟩ := take_lookup ids active [] id
        have list_guard : Erlang.erlang.«is_list/1» (Term.list ids) = .ok Term.true := by cases ids <;> rfl
        change Elixir.Map.«take/3» (Term.list ids) (.map active) .nil = .ok (.map taken) at take
        change Term.mapLookup taken id = (if requested ids id then Term.mapLookup active id else none) at taken_lookup
        have forgot : Skills.«forget/3» (.map active) (Term.list ids) (.map archive) =
            .ok (.tuple #[.map kept, .map (taken ++ archive)]) := by
          simp [Skills.«forget/3», Elixir.Map.«take/2», Elixir.Map.«drop/2», Erlang.erlang.«is_map/1»,
            list_guard, drop, take, Erlang.maps.«merge/2»]
        simp only [«forgetting_preserves_progress:ensures/4», «lookup_after_forgetting/4», forgot,
          «expected_progress/4», Erlang.maps.«find/2», Lynx.Except.ok_bind, lookup_append, kept_lookup,
          member_requested]
        cases chosen : requested ids id <;> cases known : Term.mapLookup active id <;>
          cases saved : Term.mapLookup archive id <;>
          simp_all [Erlang.erlang.«=:=/2»]
      """
  end
end
