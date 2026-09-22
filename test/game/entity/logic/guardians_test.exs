defmodule ThistleTea.Game.Entity.Logic.GuardiansTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Guardians
  alias ThistleTea.Game.Entity.Logic.MiniPet
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:owner]

  describe "prepare/2" do
    test "direct casts toggle only matching guardians", %{owner: owner} do
      owner =
        owner |> Guardians.activate(ref(2, 10)) |> Guardians.activate(ref(3, 10)) |> Guardians.activate(ref(4, 20))

      {removed, false} = Guardians.prepare(owner, request())
      assert Guardians.active(removed) == [ref(4, 20)]
      assert Companion.active_guid(removed) == 88
      assert MiniPet.active_ref(removed).guid == 99
      assert removed.unit.summon == 88
      assert Enum.sort(Enum.map(removed.internal.events, & &1.target_guid)) == [2, 3]
      assert {^owner, true} = Guardians.prepare(owner, %{request() | triggered?: true})
      assert {^removed, true} = Guardians.prepare(owner, %{request() | replace?: true})
      assert Guardians.removed(removed, 2) == removed
    end

    test "creature casters stop adding an entry once sixteen are active", %{owner: owner} do
      mob = %Mob{object: owner.object, unit: owner.unit, internal: %Internal{}}
      fifteen = Enum.reduce(1..15, mob, &Guardians.activate(&2, ref(&1, 10)))
      assert {^fifteen, true} = Guardians.prepare(fifteen, request())
      sixteen = Guardians.activate(fifteen, ref(16, 10))
      assert {^sixteen, false} = Guardians.prepare(sixteen, request())
      assert {^sixteen, true} = Guardians.prepare(sixteen, %{request() | entry: 20})
    end
  end

  describe "dismiss_all/1" do
    test "clears the collection once", %{owner: owner} do
      owner = Guardians.activate(owner, ref(2, 10))
      removed = Guardians.dismiss_all(owner)
      assert Guardians.active(removed) == []
      assert [%Effects.DespawnEntity{target_guid: 2}] = removed.internal.events
      assert Guardians.dismiss_all(removed) == removed
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
end
