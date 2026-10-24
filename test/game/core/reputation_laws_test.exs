defmodule ThistleTea.Game.Core.ReputationLawsTest do
  use ExUnit.Case, async: true
  use Lynx.Case

  alias ThistleTea.Game.Core.Reputation

  def minimum(:hated), do: -42_000
  def minimum(:hostile), do: -6_000
  def minimum(:unfriendly), do: -3_000
  def minimum(:neutral), do: 0
  def minimum(:friendly), do: 3_000
  def minimum(:honored), do: 9_000
  def minimum(:revered), do: 21_000
  def minimum(:exalted), do: 42_000

  def next(:hated), do: :hostile
  def next(:hostile), do: :unfriendly
  def next(:unfriendly), do: :neutral
  def next(:neutral), do: :friendly
  def next(:friendly), do: :honored
  def next(:honored), do: :revered
  def next(:revered), do: :exalted

  def bucketed?(standing, rank) do
    minimum(rank) <= standing and (rank === :exalted or standing < minimum(next(rank)))
  end

  laws "Reputation.rank/1", options: [maxHeartbeats: 1_000_000] do
    cutoff &Enumerable.reduce/3
    cutoff &Enumerable.count/1
    cutoff &Enumerable.member?/2
    cutoff &Enumerable.slice/1
    cutoff &Protocol.UndefinedError.exception/1
    cutoff &Enum.reduce_range/5

    law rank_bucket(standing),
      requires: is_integer(standing) and standing >= -42_000,
      expects: bucketed?(standing, Reputation.rank(standing)),
      proof: ~LEAN"""
      open Lynx Elixir.ThistleTea.Game.Core in
        have rank_eq (d : Nat) (s : Int) :
            Reputation.«rank/1» (Dispatcher.ofTable Erlang.program.fun_table d) (.integer s) =
              .ok (.atom (if 42000 ≤ s then "exalted" else if 21000 ≤ s then "revered" else if 9000 ≤ s then "honored"
                else if 3000 ≤ s then "friendly" else if 0 ≤ s then "neutral" else if -3000 ≤ s then "unfriendly"
                else if -6000 ≤ s then "hostile" else "hated")) := by
          simp [Reputation.«rank/1», Reputation.lynx_literal_xus2gjyg, Elixir.Enum.«reverse/1», Erlang.lists.«reverse/2»,
            Elixir.Enum.«find_value/3», Elixir.Enum.«find_value_list/3», Reputation.«$lynx_fun_4/2», Term.list,
            Erlang.erlang.«is_list/1», Lynx.Except.tryWith_ok]
          by_cases h7 : 42000 ≤ s <;> simp [h7]
          by_cases h6 : 21000 ≤ s <;> simp [h6]
          by_cases h5 : 9000 ≤ s <;> simp [h5]
          by_cases h4 : 3000 ≤ s <;> simp [h4]
          by_cases h3 : 0 ≤ s <;> simp [h3]
          by_cases h2 : -3000 ≤ s <;> simp [h2]
          by_cases h1 : -6000 ≤ s <;> simp [h1]
          by_cases h0 : -42000 ≤ s <;> simp [h0]
        simp only [«rank_bucket:requires/1»] at requires
        cases standing <;> simp [Erlang.erlang.«is_integer/1»] at requires
        rename_i s
        simp only [Lynx.apply_eq, «rank_bucket:ensures/1», rank_eq, Lynx.Except.ok_bind]
        by_cases h7 : 42000 ≤ s <;> simp [h7, «bucketed?/2», «minimum/1», «next/1», Erlang.erlang.«=:=/2»] <;> try omega
        by_cases h6 : 21000 ≤ s <;> simp [h6, «bucketed?/2», «minimum/1», «next/1», Erlang.erlang.«=:=/2»] <;> try omega
        by_cases h5 : 9000 ≤ s <;> simp [h5, «bucketed?/2», «minimum/1», «next/1», Erlang.erlang.«=:=/2»] <;> try omega
        by_cases h4 : 3000 ≤ s <;> simp [h4, «bucketed?/2», «minimum/1», «next/1», Erlang.erlang.«=:=/2»] <;> try omega
        by_cases h3 : 0 ≤ s <;> simp [h3, «bucketed?/2», «minimum/1», «next/1», Erlang.erlang.«=:=/2»] <;> try omega
        by_cases h2 : -3000 ≤ s <;> simp [h2, «bucketed?/2», «minimum/1», «next/1», Erlang.erlang.«=:=/2»] <;> try omega
        by_cases h1 : -6000 ≤ s <;> simp [h1, «bucketed?/2», «minimum/1», «next/1», Erlang.erlang.«=:=/2»] <;> try omega
        have below : s < -6000 := by omega
        simp [requires, below]
      """
  end
end
