defmodule ThistleTea.Game.World.Entity.EffectResolver.ControlDeviceDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Effects.RandomChoice
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.PlayerPossession
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  @moduletag :dbc_db

  setup [:entities]

  describe "resolve/2" do
    test "the remote hands possession to the caster's channel owner", %{caster: caster, machine: machine} do
      trigger = outcome(caster, machine, 8344, 1)
      caster_guid = caster.object.guid
      target_guid = machine.object.guid

      assert [%Effects.TriggerSpellRequest{source_guid: ^caster_guid, target_guid: ^target_guid, spell_id: 8345}] =
               Spells.resolve(machine, trigger)

      assert [%Effects.StartTriggeredChannel{spell: spell, context: context, targets: targets}] =
               Spells.resolve(caster, trigger)

      assert spell.id == 8345
      assert Spell.attribute?(spell, :channeled)
      assert spell.duration_ms == 60_000
      assert context.caster_guid == caster_guid
      assert Target.unit_guid(targets) == target_guid
    end

    test "remote malfunctions root or enrage the machine and expire normally", %{caster: caster, machine: machine} do
      root = outcome(caster, machine, 8344, 2)
      {rooted, _} = deliver(caster, machine, root)
      assert Aura.rooted?(rooted)
      assert hd(rooted.unit.auras).caster_guid == caster.object.guid
      {released, _} = Aura.tick(rooted, 21_000)
      refute Aura.rooted?(released)
      refute Aura.has_spell?(released, 8346)

      enrage = outcome(caster, machine, 8344, 3)
      {enraged, _} = deliver(machine, machine, enrage)
      assert hd(enraged.unit.auras).caster_guid == machine.object.guid
      assert Aura.flat_amount(enraged, :mod_damage_done) == 30
      assert Aura.flat_amount(enraged, :mod_melee_haste) == 30
      {released, _} = Aura.tick(enraged, 121_000)
      refute Aura.has_spell?(released, 8599)
    end

    test "cap backfires reverse the control owner and release at expiry", %{caster: caster, victim: victim} do
      for {roll, source, recipient} <- [{3, caster, victim}, {2, victim, caster}] do
        trigger = outcome(caster, victim, 13_180, roll)
        {controlled, events} = deliver(source, recipient, trigger)
        assert PlayerPossession.charmed?(controlled)
        assert PlayerPossession.controller(controlled) == source.object.guid
        assert controlled.unit.faction_template == source.unit.faction_template
        assert Enum.any?(events, &is_struct(&1, Effects.ControlGranted))

        {released, events} = Aura.tick(controlled, 21_000)
        refute PlayerPossession.active?(released)
        assert released.unit.faction_template == recipient.unit.faction_template
        assert released.unit.charmed_by == 0
        assert Enum.any?(events, &is_struct(&1, Effects.ControlReleased))
      end
    end
  end

  defp outcome(caster, target, id, roll) do
    spell = SpellLoader.load(id)
    context = CastContext.from_caster(caster, spell, target.object.guid)
    {_, [%RandomChoice{} = choice]} = SpellEffect.receive(target, context, spell, 0)
    [trigger] = RandomChoice.select(choice, roll)
    trigger
  end

  defp deliver(source, target, trigger) do
    events = Spells.resolve(source, trigger)

    [%Effects.DeliverSpell{spell: spell, cast_context: context}] =
      Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))

    assert context.caster_guid == source.object.guid
    assert context.target_guid == target.object.guid
    SpellEffect.receive(target, context, spell, 1_000)
  end

  defp entities(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    caster = character(1, world)
    victim = character(2, world)

    machine = %Mob{
      object: %Object{guid: Guid.runtime(:mob, 36)},
      unit: %Unit{level: 30, health: 1_000, max_health: 1_000, faction_template: 14, auras: []},
      internal: %Internal{world: world},
      movement_block: movement()
    }

    for {entity, type, creature_type} <- [{caster, :players, 7}, {victim, :players, 7}, {machine, :mobs, 9}] do
      guid = entity.object.guid
      SpatialHash.insert(type, guid, world, 0.0, 0.0, 0.0)

      Metadata.put(guid, %{
        alive?: true,
        level: entity.unit.level,
        unit_flags: 0,
        creature_type: creature_type,
        no_spell_defense?: true
      })

      on_exit(fn ->
        Metadata.delete(guid)
        SpatialHash.remove(type, guid)
      end)
    end

    %{caster: caster, victim: victim, machine: machine}
  end

  defp character(faction, world) do
    %Character{
      object: %Object{guid: Guid.from_low_guid(:player, System.unique_integer([:positive]))},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, faction_template: faction, flags: 8, auras: []},
      player: %Player{},
      internal: %Internal{world: world},
      movement_block: movement()
    }
  end

  defp movement, do: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
end
