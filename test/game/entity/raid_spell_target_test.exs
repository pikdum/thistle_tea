defmodule ThistleTea.Game.Entity.RaidSpellTargetTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Spells
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.SpellTargetResolver
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.World.System.Duel, as: DuelSystem
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.WorldRef

  setup [:raid]

  describe "resolve/3" do
    test "crosses raid subgroups and includes pets while excluding the carrier and unrelated allies", context do
      %{carrier: carrier, member: member, outsider: outsider, spell: spell} = context
      pet = pet(member, 2.0)

      assert recipients(carrier, spell, outsider) == Enum.sort([member.object.guid, pet.object.guid])
      {:ok, _} = PartySystem.change_subgroup(carrier.object.guid, member.object.guid, 0)
      assert recipients(carrier, spell, outsider) == Enum.sort([member.object.guid, pet.object.guid])

      move(member, 20.0)
      assert recipients(carrier, spell, outsider) == [pet.object.guid]
      move(pet, 5.01)
      assert recipients(carrier, spell, outsider) == []
    end

    test "filters level and hostility on the pet owner before applying the target cap", context do
      %{carrier: carrier, member: member, outsider: outsider, spell: spell} = context
      pet = pet(member, 2.0)
      spell = %{spell | max_targets: 1}
      Metadata.update(member.object.guid, %{level: 9})
      assert recipients(carrier, spell, outsider) == []
      Metadata.update(member.object.guid, %{level: 10})
      assert [guid] = recipients(carrier, spell, outsider)
      assert guid in [member.object.guid, pet.object.guid]

      for {source, target} <- [{carrier, member}, {member, carrier}] do
        guid = source.object.guid
        :ets.insert(DuelSystem, {guid, %{opponent_guid: target.object.guid, state: :started}})
        Metadata.update(guid, %{duel_started?: true})
        on_exit(fn -> :ets.delete(DuelSystem, guid) end)
      end

      assert recipients(carrier, spell, outsider) == []
    end

    test "uses current world and living state for members and pets independently", context do
      %{carrier: carrier, member: member, outsider: outsider, spell: spell} = context
      pet = pet(member, 2.0)
      Metadata.update(member.object.guid, %{alive?: false})
      assert recipients(carrier, spell, outsider) == [pet.object.guid]
      Metadata.update(pet.object.guid, %{alive?: false})
      assert recipients(carrier, spell, outsider) == []
      Metadata.update(member.object.guid, %{alive?: true})
      SpatialHash.update(:players, member.object.guid, WorldRef.instance(0, 0), 3.0, 0.0, 0.0)
      assert recipients(carrier, spell, outsider) == []
    end

    test "pet casts use their current owner and exclude the casting pet", context do
      %{carrier: carrier, member: member, outsider: outsider, spell: spell} = context
      pet = pet(carrier, 2.0)
      pet = %{pet | unit: %{pet.unit | created_by: outsider.object.guid}}

      assert recipients(pet, spell, outsider) == Enum.sort([carrier.object.guid, member.object.guid])
      pet = %{pet | unit: %{pet.unit | charmed_by: outsider.object.guid}}
      assert recipients(pet, spell, member) == [outsider.object.guid]
    end

    test "ungrouped owners and pets affect only one another", context do
      %{carrier: carrier, member: member, outsider: outsider, spell: spell} = context
      pet = pet(carrier, 2.0)
      pet(member, 2.0)
      PartySystem.leave(member.object.guid)
      assert recipients(carrier, spell, outsider) == [pet.object.guid]
      assert recipients(pet, spell, outsider) == [carrier.object.guid]
    end

    test "radius modifiers use the carrier's auras and removal restores the boundary", context do
      %{carrier: carrier, member: member, outsider: outsider, spell: spell} = context
      spell = %{spell | spell_family: 3, family_flags_0: 0x40}
      move(member, 6.0)

      holder = %Holder{
        spell: %Spell{id: 999_902, spell_family: 3},
        auras: [%AuraData{type: :add_pct_modifier, misc_value: 6, class_mask: 0x40, amount: 20}]
      }

      modified = %{carrier | unit: %{carrier.unit | auras: [holder]}}
      assert recipients(carrier, spell, outsider) == []
      assert recipients(modified, spell, outsider) == [member.object.guid]
      {removed, _events} = Aura.remove_spells(modified, [999_902], 0)
      assert recipients(removed, spell, outsider) == []
    end
  end

  describe "periodic raid triggers" do
    @tag :dbc_db
    test "Plague ticks around the carrier while retaining damage attribution and stopping on cleanup", context do
      %{carrier: carrier, member: member, outsider: outsider} = context
      source_guid = Guid.runtime(:mob, 1)

      for {parent_id, child_id} <- [{22_997, 19_594}, {26_556, 26_557}] do
        parent = SpellLoader.load(parent_id)
        child = SpellLoader.load(child_id)
        assert [%{amplitude_ms: 3_000, trigger_spell_id: ^child_id}] = parent.effects
        hit = %CastContext{caster_guid: source_guid, caster_level: 60, spell: parent}
        {afflicted, _events} = Aura.apply_spell(carrier, hit, parent, 0)
        {ticked, events} = Aura.tick(afflicted, 3_000)
        trigger = Enum.find(events, &is_struct(&1, Effects.TriggerSpell))
        assert trigger.source_guid == source_guid
        assert ticked.unit.health == carrier.unit.health
        resolved = Spells.resolve(ticked, trigger)
        member_guid = member.object.guid

        assert [%Effects.SpellGo{source_guid: ^source_guid, hit_guids: [^member_guid]} | _] = resolved
        assert [%Effects.DeliverSpell{} = delivery] = Enum.filter(resolved, &is_struct(&1, Effects.DeliverSpell))
        assert delivery.target_guid == member_guid
        assert delivery.cast_context.caster_guid == source_guid
        assert delivery.cast_context.caster_level == 60
        {damaged, feedback} = SpellEffect.receive(member, delivery.cast_context, child, 3_000)
        assert damaged.unit.health < member.unit.health
        assert Enum.any?(feedback, &match?(%Effects.SpellDamage{source_guid: ^source_guid}, &1))

        move(member, 6.0)
        assert recipients(ticked, child, outsider) == []
        move(member, 3.0)

        {undispelled, _events} = Aura.dispel(ticked, 3, 3_100, :negative)
        assert undispelled.unit.auras == ticked.unit.auras
        {removed, _events} = Aura.remove_spells(ticked, [parent_id], 3_100)
        {expired, _events} = Aura.tick(ticked, 40_000)
        killed = Core.take_damage(ticked, 100_000, 3_100)

        for cleaned <- [removed, expired, killed] do
          assert cleaned.unit.auras == []
          assert Aura.next_event_at(cleaned) == nil
          {_entity, events} = Aura.tick(cleaned, 43_000)
          refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
        end
      end
    end
  end

  defp recipients(caster, spell, selected) do
    caster |> SpellTargetResolver.resolve(spell, Target.unit(selected.object.guid)) |> Enum.sort()
  end

  defp raid(_context) do
    world = WorldRef.instance(0, System.unique_integer([:positive]))
    carrier = character(world, 0.0)
    member = character(world, 3.0)
    outsider = character(world, 2.0)
    :ok = PartySystem.invite(carrier.object.guid, "Carrier", member.object.guid)
    {:ok, _} = PartySystem.accept(member.object.guid, "Member")
    {:ok, _} = PartySystem.convert_raid(carrier.object.guid)
    {:ok, _} = PartySystem.change_subgroup(carrier.object.guid, member.object.guid, 1)
    on_exit(fn -> Enum.each([carrier, member], &PartySystem.leave(&1.object.guid)) end)

    spell = %Spell{
      id: 999_901,
      spell_level: 20,
      effects: [%Effect{type: :school_damage, implicit_target_a: :raid_around_caster, radius_yards: 5.0}]
    }

    %{carrier: carrier, member: member, outsider: outsider, spell: spell}
  end

  defp character(world, x) do
    guid = Guid.from_low_guid(:player, System.unique_integer([:positive]))

    %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 5_000, max_health: 5_000, level: 60, auras: []},
      player: %Player{},
      movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world}
    }
    |> publish(:players)
  end

  defp pet(owner, x) do
    guid = Guid.runtime(:pet, 1)

    entity =
      %Mob{
        object: %Object{guid: guid},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 1, auras: []},
        movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}},
        internal: %Internal{world: owner.internal.world, pet: %Pet{owner_guid: owner.object.guid}}
      }
      |> publish(:mobs)

    Metadata.update(guid, %{owner_guid: owner.object.guid})
    entity
  end

  defp publish(entity, table) do
    guid = entity.object.guid
    {x, y, z, _o} = entity.movement_block.position
    SpatialHash.insert(table, guid, entity.internal.world, x, y, z)

    Metadata.put(guid, %{
      alive?: true,
      level: entity.unit.level,
      unit_flags: 0,
      no_spell_defense?: true,
      faction_can_have_reputation?: false,
      faction_template: %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
    })

    on_exit(fn ->
      SpatialHash.remove(table, guid)
      Metadata.delete(guid)
    end)

    entity
  end

  defp move(entity, x) do
    table = if is_struct(entity, Character), do: :players, else: :mobs
    SpatialHash.update(table, entity.object.guid, entity.internal.world, x, 0.0, 0.0)
  end
end
