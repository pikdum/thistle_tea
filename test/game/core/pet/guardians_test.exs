defmodule ThistleTea.Game.Core.Pet.GuardiansTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Guardian
  alias ThistleTea.Game.Core.Entity.Component.Internal.Pet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Pet.Companion
  alias ThistleTea.Game.Core.Pet.Companion.EntityRef
  alias ThistleTea.Game.Core.Pet.Guardians
  alias ThistleTea.Game.Core.Pet.MiniPet
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Cooldowns
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context

  setup [:owner]

  describe "prepare/3" do
    test "direct casts toggle only matching guardians", %{owner: owner} do
      owner =
        owner |> Guardians.activate(ref(2, 10)) |> Guardians.activate(ref(3, 10)) |> Guardians.activate(ref(4, 20))

      {removed, false} = Guardians.prepare(owner, request(), 1000)
      assert Guardians.active(removed) == [ref(4, 20)]
      assert Companion.active_guid(removed) == 88
      assert MiniPet.active_ref(removed).guid == 99
      assert removed.unit.summon == 88
      assert Enum.sort(Enum.map(removed.internal.events, & &1.target_guid)) == [2, 3]
      assert {^owner, true} = Guardians.prepare(owner, %{request() | triggered?: true}, 1000)
      assert {^removed, true} = Guardians.prepare(owner, %{request() | replace?: true}, 1000)
      assert Guardians.removed(removed, 2, 1000) == removed
    end

    test "creature casters stop adding an entry once sixteen are active", %{owner: owner} do
      mob = %Mob{object: owner.object, unit: owner.unit, internal: %Internal{}}
      fifteen = Enum.reduce(1..15, mob, &Guardians.activate(&2, ref(&1, 10)))
      assert {^fifteen, true} = Guardians.prepare(fifteen, request(), 1000)
      sixteen = Guardians.activate(fifteen, ref(16, 10))
      assert {^sixteen, false} = Guardians.prepare(sixteen, request(), 1000)
      assert {^sixteen, true} = Guardians.prepare(sixteen, %{request() | entry: 20}, 1000)
    end
  end

  describe "dismiss_all/2" do
    test "departure activates the retained item cooldown before the owner is saved", %{owner: owner} do
      spell = deferred_spell()
      ref = %{ref(2, 2675) | cooldown_started_at: 100}
      owner = owner |> Cooldowns.start(spell, 100, 4384) |> Guardians.activate(ref)
      removed = Guardians.dismiss_all(owner, 1000)
      assert Cooldowns.pending(removed, 500) == nil
      assert Cooldowns.ready_at(removed, spell) == 61_000
      assert [%{item_id: 4384, category_ms: 60_000}] = Cooldowns.initial(removed, %{}, 1000)
      assert [%Effects.CooldownEvent{spell_id: 500}, %Effects.DespawnEntity{target_guid: 2}] = removed.internal.events
      assert Guardians.removed(removed, 2, 2000) == removed
    end

    test "an old guardian cannot activate a newer cast", %{owner: owner} do
      spell = deferred_spell()

      owner =
        owner |> Cooldowns.start(spell, 200, 4384) |> Guardians.activate(%{ref(2, 2675) | cooldown_started_at: 100})

      removed = Guardians.removed(owner, 2, 1000)
      assert Cooldowns.pending(removed, 500).started_at == 200
      assert removed.internal.events == []
    end

    test "clears the collection once", %{owner: owner} do
      owner = Guardians.activate(owner, ref(2, 10))
      removed = Guardians.dismiss_all(owner, 1000)
      assert Guardians.active(removed) == []
      assert [%Effects.DespawnEntity{target_guid: 2}] = removed.internal.events
      assert Guardians.dismiss_all(removed, 1000) == removed
    end
  end

  describe "on_death/1" do
    test "lethal damage releases the summoning cast once through the death transition", %{owner: owner} do
      guardian = %Mob{
        object: %Object{guid: 2},
        unit: %{owner.unit | created_by_spell: 500, max_health: 100},
        movement_block: owner.movement_block,
        internal: %Internal{
          guardian: %Guardian{cooldown_started_at: 100},
          pet: %Pet{owner_guid: 1, kind: :guardian}
        }
      }

      dead = Entity.take_damage(guardian, 100, 1000)
      assert dead.unit.health == 0

      assert [%Effects.ActivateCooldown{target_guid: 1, spell_id: 500, started_at: 100}] =
               Enum.filter(dead.internal.events, &is_struct(&1, Effects.ActivateCooldown))

      assert dead.internal.guardian.cooldown_started_at == nil
      assert Guardians.on_death(dead) == dead
    end
  end

  describe "SpellEffect.receive/4" do
    test "executes once on its caster with count item and trigger context", %{owner: owner} do
      spell = %Spell{
        id: 500,
        duration_ms: 6000,
        category: 1,
        effects: [
          %Effect{
            type: :summon_guardian,
            misc_value: 10,
            base_points: 2,
            base_dice: 1,
            implicit_target_a: :minion_position,
            radius_yards: 2.0,
            multiple_value: -5.0
          }
        ]
      }

      context = %CastContext{caster_guid: 1, caster_level: 60, cast_item_guid: 55, triggered?: true}
      assert {^owner, [%Effects.SummonGuardians{} = effect]} = SpellEffect.receive(owner, context, spell, 1000)
      assert effect.count == 3
      assert effect.duration_ms == 6000
      assert effect.level_offset == -5.0
      assert effect.cast_item_guid == 55
      assert effect.triggered?
      assert effect.replace?
      {x, y, z, _} = effect.position
      assert_in_delta x, :math.sqrt(2), 0.001
      assert_in_delta y, :math.sqrt(2), 0.001
      assert z == 0.0
      assert {^owner, []} = SpellEffect.receive(owner, %{context | caster_guid: 2}, spell, 1000)
    end
  end

  describe "EventSink.emit/3" do
    test "routes both caster kinds to an explicit owner process", %{owner: owner} do
      effect = request()
      EventSink.emit(owner, effect)
      refute_received ^effect
      EventSink.emit(owner, effect, Context.new(self()))
      assert_received ^effect
      EventSink.emit(%Mob{}, effect, Context.new(self()))
      assert_received ^effect
    end
  end

  defp owner(_context) do
    owner = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, level: 60},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    owner = owner |> Companion.activate(:guardian, ref(88, 416)) |> MiniPet.activate(ref(99, 2671))
    %{owner: owner}
  end

  defp ref(guid, entry), do: %EntityRef{guid: guid, entry: entry, spell_id: 500}
  defp request, do: %Effects.SummonGuardians{entry: 10, spell_id: 500, count: 1, duration_ms: 0}

  defp deferred_spell do
    %Spell{id: 500, attributes: MapSet.new([:cooldown_on_event]), category: 24, category_recovery_time_ms: 60_000}
  end
end
