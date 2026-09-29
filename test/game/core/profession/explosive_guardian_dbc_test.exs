defmodule ThistleTea.Game.Core.Profession.ExplosiveGuardianDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Guardian
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.PetSpellModifiers
  alias ThistleTea.Game.Core.Profession.Engineering
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.EffectResolver.Spells
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  @moduletag :dbc_db
  @spells [3617, 4050, 4051, 13_259, 13_260, 13_261]

  setup [:entities]

  describe "reactions/3" do
    test "the first landed swing spends its sole charge and requests a blast", %{
      guardian: guardian,
      enemies: [enemy | _] = enemies
    } do
      for {entry, explosion} <- [{2675, 4050}, {8937, 13_259}] do
        passive = SpellLoader.load(Engineering.guardian_passive(entry))
        armed = PetSpellModifiers.apply_passive(guardian, passive, 0)
        assert [%{charges: 1}] = armed.unit.auras
        context = %{victim_guid: enemy.object.guid, outcome: :miss, proc_type: :deal_melee_swing, now: 1000}
        assert {^armed, []} = Aura.reactions(armed, :melee_hit_dealt, context)
        {spent, events} = Aura.reactions(armed, :melee_hit_dealt, %{context | outcome: :normal})
        assert spent.unit.auras == []

        assert [%Effects.TriggerSpell{spell_id: ^explosion} = trigger] =
                 Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))

        assert trigger.source_guid == guardian.object.guid
        assert trigger.target_guid == enemy.object.guid
        assert {^spent, []} = Aura.reactions(spent, :melee_hit_dealt, %{context | outcome: :normal})
        assert_blast(spent, trigger, explosion, enemies)
      end
    end
  end

  describe "resolve/2" do
    test "explosions damage each nearby enemy and quietly kill only the summon", %{guardian: guardian, enemies: enemies} do
      for id <- [4050, 13_259] do
        trigger = Effects.trigger_spell(guardian.object.guid, 60, hd(enemies).object.guid, id)
        assert_blast(guardian, trigger, id, enemies)
      end
    end

    test "an idle expiration still kills its caster when there are no enemy recipients", %{
      guardian: guardian,
      enemies: enemies
    } do
      Enum.each(enemies, &SpatialHash.remove(:mobs, &1.object.guid))

      for id <- [4050, 13_259] do
        events = Spells.resolve(guardian, Effects.trigger_spell(guardian.object.guid, 60, guardian.object.guid, id))
        assert [delivery] = deliveries(events)
        assert delivery.target_guid == guardian.object.guid
        assert delivery.cast_context.effect_indices == [1, 2]
        assert_suicide(guardian, delivery)
      end
    end

    test "solo malfunctions hit the caster without damaging unrelated units", %{
      guardian: guardian,
      friend: friend
    } do
      trigger = Effects.trigger_spell(guardian.object.guid, 60, guardian.object.guid, 13_261, resolve_targets?: true)
      recipients = Spells.resolve(guardian, trigger) |> deliveries()
      assert [delivery] = recipients
      assert delivery.target_guid == guardian.object.guid
      refute delivery.target_guid == friend.object.guid
      {damaged, events} = SpellEffect.receive(guardian, delivery.cast_context, delivery.spell, 1000)
      assert (guardian.unit.health - damaged.unit.health) in 315..385
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
    end
  end

  defp assert_blast(guardian, trigger, id, enemies) do
    recipients = Spells.resolve(guardian, trigger) |> deliveries()

    assert Enum.sort(Enum.map(recipients, & &1.target_guid)) ==
             Enum.sort([guardian.object.guid | Enum.map(enemies, & &1.object.guid)])

    for target <- enemies do
      delivery = Enum.find(recipients, &(&1.target_guid == target.object.guid))
      assert delivery.cast_context.effect_indices == [0]
      {damaged, events} = SpellEffect.receive(target, delivery.cast_context, delivery.spell, 1000)
      assert (target.unit.health - damaged.unit.health) in if(id == 4050, do: 135..165, else: 315..385)
      refute Enum.any?(events, &is_struct(&1, Effects.TriggerSpell))
    end

    delivery = Enum.find(recipients, &(&1.target_guid == guardian.object.guid))
    assert delivery.cast_context.effect_indices == [1, 2]
    assert_suicide(guardian, delivery)
  end

  defp assert_suicide(guardian, delivery) do
    {unchanged, events} = SpellEffect.receive(guardian, delivery.cast_context, delivery.spell, 1000)
    assert unchanged.unit.health == guardian.unit.health
    assert [%Effects.TriggerSpell{spell_id: 3617} = suicide] = events
    assert suicide.target_guid == guardian.object.guid
    assert [delivery] = guardian |> Spells.resolve(suicide) |> deliveries()
    {dead, _events} = SpellEffect.receive(guardian, delivery.cast_context, delivery.spell, 1000)
    assert dead.unit.health == 0
    assert Enum.any?(dead.internal.events, &match?(%Effects.ActivateCooldown{target_guid: 1, started_at: 100}, &1))
  end

  defp deliveries(events), do: Enum.filter(events, &is_struct(&1, Effects.DeliverSpell))

  defp entities(_context) do
    spells = Map.new(@spells, &{&1, SpellLoader.load(&1)})
    guardian = entity(0.0, friendly(), spells)

    guardian = %{
      guardian
      | internal: %{
          guardian.internal
          | guardian: %Guardian{cooldown_started_at: 100},
            pet: %Pet{owner_guid: 1, kind: :guardian}
        }
    }

    enemies = [entity(2.0, hostile(), spells), entity(3.0, hostile(), spells)]
    friend = entity(1.0, friendly(), spells)
    entity(20.0, hostile(), spells)
    %{guardian: guardian, enemies: enemies, friend: friend}
  end

  defp entity(x, faction, spells) do
    guid = Guid.from_low_guid(:mob, 2675, rem(System.unique_integer([:positive]), 0xFFFFFF))
    world = WorldRef.open(998)
    SpatialHash.update(:mobs, guid, world, x, 0.0, 0.0)

    Metadata.put(guid, %{
      alive?: true,
      level: 60,
      faction_template: faction,
      faction_can_have_reputation?: false,
      unit_flags: 0,
      no_spell_defense?: true
    })

    on_exit(fn ->
      SpatialHash.remove(:mobs, guid)
      Metadata.delete(guid)
    end)

    %Mob{
      object: %Object{guid: guid},
      unit: %Unit{
        health: 1000,
        max_health: 1000,
        level: 60,
        faction_template: faction.id,
        auras: [],
        created_by_spell: 4074
      },
      internal: %Internal{world: world, spellbook: spells},
      movement_block: %MovementBlock{position: {x, 0.0, 0.0, 0.0}, movement_flags: 0}
    }
  end

  defp friendly, do: %FactionTemplate{id: 1, faction: 1, faction_group: 3, friend_group: 2, enemy_group: 12}
  defp hostile, do: %FactionTemplate{id: 17, faction: 15, faction_group: 8, friend_group: 0, enemy_group: 1}
end
