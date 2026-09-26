defmodule ThistleTea.Game.Entity.Logic.EngineeringDbcTest do
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
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Effects.RandomChoice
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db
  @spells [13_120, 13_099, 16_566, 13_119, 13_139, 13_138]

  setup [:entities]

  describe "receive/4" do
    test "Net-o-Matic hands exactly one weighted outcome back to its caster", %{caster: caster, target: target} do
      parent = SpellLoader.load(13_120)
      context = CastContext.from_caster(caster, parent, target.object.guid)
      {unchanged, [%RandomChoice{} = choice]} = SpellEffect.receive(target, context, parent, 0)
      assert unchanged.unit == target.unit
      assert RandomChoice.total_weight(choice) == 10

      assert Enum.map(1..10, fn roll -> hd(RandomChoice.select(choice, roll)).spell_id end) ==
               [16_566, 13_119 | List.duplicate(13_099, 8)]

      for roll <- 1..10 do
        [trigger] = RandomChoice.select(choice, roll)
        assert trigger.source_guid == caster.object.guid
        assert trigger.target_guid == target.object.guid
        assert trigger.cast_item_guid == nil
        assert [%Effects.TriggerSpellRequest{} = request] = Spells.resolve(target, trigger)
        assert request.target_guid == target.object.guid
        assert request.spell_id == trigger.spell_id
      end
    end

    test "normal nets root the target for ten seconds and expire through ordinary aura cleanup", context do
      delivery = delivery(context.caster, context.target.object.guid, 13_099)
      assert delivery.target_guid == context.target.object.guid
      {rooted, events} = receive_spell(context.target, delivery, 1_000)
      assert Aura.rooted?(rooted)
      assert [%{expires_at: 11_000}] = rooted.unit.auras
      assert Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: true}, &1))
      {expired, events} = Aura.tick(rooted, 11_000)
      refute Aura.rooted?(expired)
      assert expired.unit.auras == []
      assert Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: false}, &1))
    end

    test "the long backfire roots only the caster for thirty seconds", %{caster: caster, target: target} do
      delivery = delivery(caster, target.object.guid, 16_566)
      assert delivery.target_guid == caster.object.guid
      {rooted, _} = receive_spell(caster, delivery, 1_000)
      assert Aura.rooted?(rooted)
      assert [%{expires_at: 31_000}] = rooted.unit.auras
      {expired, _} = Aura.tick(rooted, 31_000)
      refute Aura.rooted?(expired)
      assert expired.unit.auras == []
    end

    test "the charging net triggers one transient marker and roots its caster despite an enemy selection", context do
      %{caster: caster, target: target} = context
      spell = SpellLoader.load(13_119)
      assert SpellTargetResolver.resolve(caster, spell, Target.unit(target.object.guid)) == [target.object.guid]
      hit = %{CastContext.from_caster(caster, spell, target.object.guid) | hit_chance_bonus: 100}
      assert hit.attack_skill == 300
      assert hit.weapon_skill_id == nil
      {rooted, events} = SpellEffect.receive(target, hit, spell, 1_000)
      assert Aura.rooted?(rooted)
      assert [%{expires_at: 21_000}] = rooted.unit.auras

      assert [%Effects.TriggerSpell{spell_id: 13_139} = marker] =
               Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))

      assert marker.target_guid == caster.object.guid
      marker_delivery = Spells.resolve(rooted, marker) |> only_delivery()
      {caster, events} = receive_spell(caster, marker_delivery, 1_000)
      assert caster.unit.auras == []
      assert [%Effects.TriggerSpell{spell_id: 13_138, target_role: :other} = backfire] = events
      backfire_delivery = Spells.resolve(caster, backfire) |> only_delivery()
      assert backfire_delivery.target_guid == caster.object.guid
      {self_rooted, _} = receive_spell(caster, backfire_delivery, 1_001)
      assert Aura.rooted?(self_rooted)
      assert [%{spell: %{id: 13_138}, expires_at: 21_001}] = self_rooted.unit.auras
      {expired, events} = Aura.tick(self_rooted, 21_001)
      refute Aura.rooted?(expired)
      assert expired.unit.auras == []
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
      dead = Core.take_damage(self_rooted, self_rooted.unit.health, 2_000)
      assert dead.unit.auras == []
      refute Enum.any?(dead.internal.events, &is_struct(&1, Effects.TriggerSpell))
    end
  end

  defp delivery(caster, target_guid, spell_id) do
    Spells.resolve(caster, Effects.trigger_spell(caster.object.guid, 60, target_guid, spell_id, resolve_targets?: true))
    |> only_delivery()
  end

  defp only_delivery(events) do
    assert [delivery] = Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))
    delivery
  end

  defp receive_spell(target, delivery, now) do
    assert delivery.cast_context.hit_outcome == :hit
    context = %{delivery.cast_context | hit_chance_bonus: 100}
    SpellEffect.receive(target, context, delivery.spell, now)
  end

  defp entities(_context) do
    target_guid = Guid.from_low_guid(:mob, System.unique_integer([:positive]), 1)
    caster_guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))
    spells = Map.new(@spells, &{&1, SpellLoader.load(&1)})
    unit = %Unit{health: 1_000, max_health: 1_000, level: 60, auras: [], target: target_guid}
    internal = %Internal{world: WorldRef.open(0), spellbook: spells}
    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}, movement_flags: 0}

    caster = %Character{
      object: %Object{guid: caster_guid},
      unit: unit,
      player: %Player{},
      internal: internal,
      movement_block: movement
    }

    target = %Mob{object: %Object{guid: target_guid}, unit: unit, internal: internal, movement_block: movement}
    Metadata.put(target_guid, %{alive?: true, level: 60, no_spell_defense?: true})
    on_exit(fn -> Metadata.delete(target_guid) end)
    %{caster: caster, target: target}
  end
end
