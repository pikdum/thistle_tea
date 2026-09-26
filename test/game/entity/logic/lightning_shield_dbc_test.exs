defmodule ThistleTea.Game.Entity.Logic.LightningShieldDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellChain
  alias ThistleTea.Game.World.Loader.SpellProcEvent
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db
  @ranks [
    {324, 26_364, 13},
    {325, 26_365, 29},
    {905, 26_366, 51},
    {945, 26_367, 80},
    {8134, 26_369, 114},
    {10_431, 26_370, 154},
    {10_432, 26_363, 198}
  ]

  setup [:catalog, :combatants]

  describe "receive_attack/4" do
    test "all ranks resolve actual damage without counter-proccing Shadowguard", %{shaman: shaman, attacker: attacker} do
      {attacker, _} = Aura.apply_spell(attacker, attacker.object.guid, 60, SpellLoader.load(19_312), 0)

      for {id, trigger, amount} <- @ranks do
        {shielded, _} = Aura.apply_spell(shaman, shaman.object.guid, 60, SpellLoader.load(id), 0)
        {shielded, events} = hit(shielded, attacker.object.guid, 1_000)
        assert [%{charges: 2, next_proc_at: 4_500}] = shielded.unit.auras
        proc = Enum.find(events, &is_struct(&1, Effects.TriggerSpell))
        assert proc.spell_id == trigger
        assert proc.triggering_spell_id == id
        delivery = shielded |> Spells.resolve(proc) |> Enum.find(&is_struct(&1, Effects.DeliverSpell))

        {damaged, events} =
          SpellEffect.receive(attacker, %{delivery.cast_context | hit_outcome: :hit}, delivery.spell, 1_000)

        assert damaged.unit.health == 5_000 - amount
        assert hd(damaged.unit.auras).charges == 3
        refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))

        assert Enum.any?(
                 events,
                 &match?(%Effects.SpellDamage{spell_id: ^trigger, damage: ^amount, proc_origin: :suppressed}, &1)
               )
      end
    end

    test "cooldown, charge exhaustion, expiry and death retain the shared lifecycle", %{
      shaman: shaman,
      attacker: attacker
    } do
      {shielded, _} = Aura.apply_spell(shaman, shaman.object.guid, 60, SpellLoader.load(10_432), 0)
      assert [%{charges: 3, expires_at: 600_000}] = shielded.unit.auras
      {expired, _} = Aura.expire_due(shielded, 600_000)
      assert expired.unit.auras == []
      assert Core.take_damage(shielded, 5_000, 1_000).unit.auras == []
      {first, _} = hit(shielded, attacker.object.guid, 1_000)
      {waiting, events} = hit(first, attacker.object.guid, 4_499)
      assert hd(waiting.unit.auras).charges == 2
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
      {second, _} = hit(waiting, attacker.object.guid, 4_500)
      assert hd(second.unit.auras).charges == 1
      {last, events} = hit(second, attacker.object.guid, 8_000)
      assert last.unit.auras == []
      assert Enum.count(events, &is_struct(&1, Effects.TriggerSpell)) == 1
      {_last, events} = hit(last, attacker.object.guid, 12_000)
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
    end
  end

  defp hit(shaman, attacker, now),
    do: Combat.receive_attack(shaman, %{caster: attacker, caster_level: 60, damage: 5}, now, roll: 9_999)

  defp catalog(_context) do
    chains =
      for {{id, _, _}, rank} <- Enum.with_index(@ranks, 1),
          do: {SpellChain, {:chain, id}, %{first_spell: 324, rank: rank, prev_spell: 0, req_spell: 0}}

    for {table, key, value} <- [{SpellProcEvent, 324, %ProcRule{cooldown_ms: 3_500}} | chains] do
      previous = :ets.lookup(table, key)
      :ets.insert(table, {key, value})

      on_exit(fn ->
        :ets.delete(table, key)
        :ets.insert(table, previous)
      end)
    end

    :ok
  end

  defp combatants(_context) do
    shaman = %Mob{
      object: %Object{guid: System.unique_integer([:positive]) + 50_000_000},
      unit: %Unit{level: 60, health: 5_000, max_health: 5_000, normal_resistance: 0, auras: []},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    attacker = %{shaman | object: %Object{guid: shaman.object.guid + 1}}
    Metadata.put(attacker.object.guid, %{alive?: true, level: 60})
    on_exit(fn -> Metadata.delete(attacker.object.guid) end)
    %{shaman: shaman, attacker: attacker}
  end
end
