defmodule ThistleTea.Game.Core.SocialLawsTest do
  use ExUnit.Case, async: true
  use Lynx.Case

  alias ThistleTea.Game.Core.Social

  def removal_preserves_membership?(owner, friends, ignored, kind, removed, probe) do
    before = %Social{owner_guid: owner, friends: %MapSet{map: friends}, ignored: %MapSet{map: ignored}}
    after_removal = Social.remove(before, kind, removed)
    other_kind = if kind === :friend, do: :ignore, else: :friend

    Social.member?(after_removal, kind, probe) ===
      (probe !== removed and Social.member?(before, kind, probe)) and
      Social.members(after_removal, other_kind) === Social.members(before, other_kind)
  end

  laws "Social.remove/3" do
    cutoff &:sets.get_slot/2
    cutoff &:sets.get_bucket/2
    cutoff &:sets.update_bucket/3
    cutoff &:sets.maybe_contract/2

    law removes_only_the_requested_membership(owner, friends, ignored, kind, removed, probe),
      requires: is_map(friends) and is_map(ignored) and kind in [:friend, :ignore],
      expects: removal_preserves_membership?(owner, friends, ignored, kind, removed, probe),
      proof: ~LEAN"""
      open Lynx Elixir.ThistleTea.Game.Core in
        simp [«removes_only_the_requested_membership:requires/6»] at requires
        cases friends <;> simp [Erlang.erlang.«is_map/1»] at requires
        cases ignored <;> simp at requires
        have hk : kind = .atom "friend" ∨ kind = .atom "ignore" := by
          by_cases friend : kind = .atom "friend"
          · exact Or.inl friend
          · exact Or.inr (requires friend)
        rcases hk with rfl | rfl <;>
          by_cases same : Term.compareExact (Term.fuel probe removed) probe removed = .eq <;>
          simp [«removes_only_the_requested_membership:ensures/6», «removal_preserves_membership?/6»,
            Social.«remove/3», Social.«member?/3», Social.«members/2», Social.«put_members/3»,
            Elixir.MapSet.«delete/2», Elixir.MapSet.«member?/2», Erlang.sets.«del_element/2»,
            Erlang.sets.«is_element/2», Erlang.maps.«remove/2», Erlang.maps.«update/3», Term.getMapKeys,
            Erlang.erlang.«is_map/1», Erlang.erlang.«=:=/2», Erlang.erlang.«=/=/2», Term.mapLookup_filter, same]
      """
  end
end
