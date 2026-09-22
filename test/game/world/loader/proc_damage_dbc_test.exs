defmodule ThistleTea.Game.World.Loader.ProcDamageDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellProcEvent

  @moduletag :dbc_db

  setup do
    chains = [
      {20_925, 20_925, 1},
      {20_927, 20_925, 2},
      {20_928, 20_925, 3},
      {20_911, 20_911, 1},
      {20_912, 20_911, 2},
      {20_913, 20_911, 3},
      {20_914, 20_911, 4},
      {7808, 7808, 1},
      {8788, 8788, 1},
      {9782, 9782, 1},
      {9784, 9784, 1},
      {16_624, 16_624, 1}
    ]

    for {id, first, rank} <- chains do
      save_entry(SpellChain, {:chain, id}, %{first_spell: first, rank: rank})
      save_entry(SpellProcEvent, id, nil)
    end

    for id <- [20_925, 20_911, 9782, 9784, 16_624] do
      :ets.insert(SpellProcEvent, {id, %ProcRule{proc_ex: 0x40}})
    end

    %{carrier: %Mob{object: %Object{guid: 1}, unit: %Unit{level: 60, auras: []}, internal: %Internal{}}}
  end

  describe "load/1" do
    test "proc damage stays distinct from unconditional damage shields" do
      for id <- [7808, 8788, 9782, 9784, 16_624, 20_911, 20_925, 20_928] do
        assert Enum.any?(SpellLoader.load(id).effects, &match?(%Effect{aura: :proc_trigger_damage}, &1))
        refute Enum.any?(SpellLoader.load(id).effects, &match?(%Effect{aura: :damage_shield}, &1))
      end
    end

    test "later ranks inherit block-only rules in individual and bulk loads", %{carrier: carrier} do
      ids = [20_925, 20_927, 20_928, 20_911, 20_912, 20_913, 20_914]
      bulk = SpellLoader.build_spellbook(ids)

      for id <- ids, spell <- [SpellLoader.load(id), bulk[id]] do
        assert spell.proc_rule.proc_ex == 0x40
        {buffed, _} = Aura.apply_spell(carrier, 1, 60, spell, 0)
        context = %{attacker_guid: 2, proc_type: :take_melee_swing, now: 1_000}
        assert {^buffed, []} = Aura.reactions(buffed, :hit_taken, Map.put(context, :outcome, :normal))
        {_updated, events} = Aura.reactions(buffed, :hit_taken, Map.put(context, :outcome, :block))
        assert Enum.any?(events, &is_struct(&1, Effects.ProcDamage)), "spell #{id}"
      end
    end

    test "an explicit higher-rank proc rule takes precedence" do
      rule = %ProcRule{proc_ex: 0x40, ppm_rate: 2.5}
      :ets.insert(SpellProcEvent, {20_928, rule})
      assert SpellLoader.load(20_928).proc_rule == rule
      assert SpellLoader.build_spellbook([20_928])[20_928].proc_rule == rule
    end

    test "Flameblade procs on outgoing melee and not incoming attacks", %{carrier: carrier} do
      {buffed, _} = Aura.apply_spell(carrier, 1, 60, SpellLoader.load(7808), 0)
      context = %{victim_guid: 2, proc_type: :deal_melee_swing, outcome: :normal, now: 1_000}
      assert {_, [%Effects.ProcDamage{effect_index: 0}]} = Aura.reactions(buffed, :melee_hit_dealt, context)
      incoming = %{attacker_guid: 2, proc_type: :take_melee_swing, outcome: :normal, now: 1_000}
      assert {^buffed, []} = Aura.reactions(buffed, :hit_taken, incoming)
    end
  end

  defp save_entry(table, key, value) do
    old = :ets.lookup(table, key)
    :ets.insert(table, {key, value})

    on_exit(fn ->
      :ets.delete(table, key)
      :ets.insert(table, old)
    end)
  end
end
