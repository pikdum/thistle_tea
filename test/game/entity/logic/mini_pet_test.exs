defmodule ThistleTea.Game.Entity.Logic.MiniPetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Companion.EntityRef
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Companion
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.MiniPet
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:character]

  describe "activate/2" do
    test "keeps combat companion identity and projections", %{character: character} do
      combat = %EntityRef{guid: 2, entry: 416, spell_id: 688}
      character = Companion.activate(character, :guardian, combat)
      active = MiniPet.activate(character, ref(3))
      assert Companion.active_ref(active) == combat
      assert active.unit.summon == 2
      assert active.unit.charm == character.unit.charm
      assert MiniPet.active_ref(active) == ref(3)
    end
  end

  describe "dismiss/1" do
    test "clears identity once and ignores stale removal", %{character: character} do
      active = MiniPet.activate(character, ref(3))
      assert MiniPet.removed(active, 4) == active
      removed = MiniPet.dismiss(active)
      assert MiniPet.active_ref(removed) == nil
      assert [%Effects.DespawnEntity{target_guid: 3}] = removed.internal.events
      assert MiniPet.dismiss(removed) == removed
    end

    test "the shared lethal damage transition dismisses both pet slots", %{character: character} do
      character = character |> Companion.activate(:guardian, ref(2)) |> MiniPet.activate(ref(3))
      dead = Core.take_damage(character, 100, 1000, environmental?: true)
      assert dead.unit.health == 0
      assert MiniPet.active_ref(dead) == nil
      assert %Effects.DespawnEntity{target_guid: 3} in dead.internal.events
      assert %Effects.DismissPet{target_guid: 2} in dead.internal.events
    end
  end

  describe "SpellEffect.receive/4" do
    test "destination summons appear beside the owner and face back", %{character: character} do
      for {target, destination} <- [{:minion_position, nil}, {47, nil}, {nil, {50.0, 60.0, 70.0}}] do
        spell = %Spell{id: 500, effects: [%Effect{type: :summon_mini_pet, misc_value: 5000, implicit_target_a: target}]}
        context = %CastContext{caster_guid: 1, caster_level: 60, destination_position: destination}

        {_, [%Effects.SummonMiniPet{position: {x, y, z, orientation}}]} =
          SpellEffect.receive(character, context, spell, 1000)

        assert_in_delta x, :math.sqrt(2), 0.001
        assert_in_delta y, :math.sqrt(2), 0.001
        assert z == 0.0
        assert_in_delta orientation, :math.pi() * 1.25, 0.001
      end
    end

    test "emits a timed critter request only for its player caster", %{character: character} do
      spell = %Spell{id: 500, duration_ms: 6000, effects: [%Effect{type: :summon_mini_pet, misc_value: 5000}]}
      context = %CastContext{caster_guid: 1, caster_level: 60}

      assert {^character, [%Effects.SummonMiniPet{entry: 5000, spell_id: 500, duration_ms: 6000}]} =
               SpellEffect.receive(character, context, spell, 1000)

      assert {^character, []} = SpellEffect.receive(character, %{context | caster_guid: 2}, spell, 1000)
      mob = %Mob{object: character.object, unit: character.unit, internal: character.internal}
      assert {^mob, []} = SpellEffect.receive(mob, context, spell, 1000)
    end
  end

  describe "EventSink.emit/3" do
    test "routes critter creation through explicit owner context", %{character: character} do
      effect = %Effects.SummonMiniPet{entry: 5000, spell_id: 500, duration_ms: 0}
      EventSink.emit(character, effect)
      refute_received ^effect
      EventSink.emit(character, effect, Context.new(self()))
      assert_received ^effect
      EventSink.emit(%Mob{}, effect, Context.new(self()))
      refute_received ^effect
    end
  end

  defp character(_context) do
    %{
      character: %Character{
        object: %Object{guid: 1},
        player: %Player{flags: 0},
        unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
        internal: %Internal{},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp ref(guid), do: %EntityRef{guid: guid, entry: 5000, spell_id: 500}
end
