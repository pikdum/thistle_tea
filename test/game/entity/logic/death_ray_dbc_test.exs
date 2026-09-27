defmodule ThistleTea.Game.Entity.Logic.DeathRayDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.Requirements
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Loader.SpellScriptName
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db
  @scripts [{13_278, "spell_gdr_channel"}, {13_493, "spell_gdr_periodic"}]

  setup [:scripts, :entities]

  describe "receive/4" do
    test "the real channel charges its caster and releases custom damage", %{caster: caster, target: target} do
      spell = caster.internal.spellbook[13_278]
      assert Spell.attribute?(spell, :channeled)
      assert spell.duration_ms == 4_000
      assert spell.semantics.channel_start_trigger_spell_id == 13_493
      caster = %{caster | internal: %{caster.internal | casting: nil}}
      caster = Casting.start(caster, spell, Target.self(caster.object.guid), 0)
      caster = Casting.resolve_requirements(caster, caster.internal.casting, %Requirements{}, 0)
      assert caster.internal.casting && caster.internal.casting.phase == :channel_tick, inspect(caster.internal.events)
      [trigger] = Enum.filter(caster.internal.events, &is_struct(&1, Effects.TriggerSpell))

      delivery = caster |> Spells.resolve(trigger) |> only_delivery()
      assert delivery.target_guid == caster.object.guid
      {caster, _} = SpellEffect.receive(caster, delivery.cast_context, delivery.spell, 0)
      [holder] = caster.unit.auras
      [aura] = holder.auras
      assert aura.amount in 100..500
      assert aura.amplitude_ms == 1_000

      {caster, events} =
        Enum.reduce(1..4, {caster, []}, fn tick, {current, previous} ->
          {current, events} = Aura.tick(current, tick * 1_000)
          {current, previous ++ events}
        end)

      assert caster.unit.health == 5_000 - 4 * aura.amount
      assert caster.unit.auras == []
      [discharge] = Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))
      assert discharge.amount == 4 * aura.amount
      assert discharge.spell_id == 13_279
      delivery = caster |> Spells.resolve(discharge) |> only_delivery()
      context = %{delivery.cast_context | hit_chance_bonus: 100, spell_crit_chance: 0}
      {target, events} = SpellEffect.receive(target, context, delivery.spell, 4_000)
      assert target.unit.health == 5_000 - discharge.amount
      assert [%Effects.SpellDamage{damage: damage}] = Enum.filter(events, &is_struct(&1, Effects.SpellDamage))
      assert damage == discharge.amount

      Metadata.update(target.object.guid, %{alive?: false})
      assert Spells.resolve(caster, discharge) == []
      Metadata.delete(target.object.guid)
      assert Spells.resolve(caster, discharge) == []
    end
  end

  defp only_delivery(events) do
    assert [delivery] = Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))
    delivery
  end

  defp scripts(_context) do
    previous = Enum.flat_map(@scripts, fn {id, _script} -> :ets.lookup(SpellScriptName, id) end)
    :ets.insert(SpellScriptName, @scripts)

    on_exit(fn ->
      Enum.each(@scripts, fn {id, _script} -> :ets.delete(SpellScriptName, id) end)
      :ets.insert(SpellScriptName, previous)
    end)

    :ok
  end

  defp entities(_context) do
    target_guid = Guid.from_low_guid(:mob, System.unique_integer([:positive]), 1)
    caster_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    spells = Map.new([13_278, 13_279, 13_493], &{&1, SpellLoader.load(&1)})
    cast = %{Cast.new(spells[13_278], Target.unit(target_guid), 0) | phase: :channel_tick}
    unit = %Unit{health: 5_000, max_health: 5_000, level: 60, auras: [], target: target_guid}
    internal = %Internal{world: WorldRef.open(0), spellbook: spells}
    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}

    caster = %Character{
      object: %Object{guid: caster_guid},
      unit: unit,
      player: %Player{},
      internal: %{internal | casting: cast},
      movement_block: movement
    }

    target = %Mob{object: %Object{guid: target_guid}, unit: unit, internal: internal, movement_block: movement}
    Metadata.put(target_guid, %{alive?: true, level: 60, no_spell_defense?: true})
    on_exit(fn -> Metadata.delete(target_guid) end)
    %{caster: caster, target: target}
  end
end
