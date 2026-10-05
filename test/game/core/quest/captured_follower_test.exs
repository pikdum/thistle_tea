defmodule ThistleTea.Game.Core.Quest.CapturedFollowerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Quest.CapturedFollower
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  describe "tick/3" do
    test "capture auras schedule two-second checks and keep the latest live creature observation" do
      for {spell_id, entry} <- [{21_827, 10_981}, {21_863, 10_990}] do
        {character, context, caster} = captured(spell_id, entry)
        [holder] = character.unit.auras
        assert holder.auras |> hd() |> Map.fetch!(:next_tick_at) == 2_000
        assert Aura.next_event_at(character) == 2_000
        {early, events} = Aura.tick(character, 1_999)
        assert early.unit.auras == character.unit.auras
        assert events == []
        {ticked, events} = Aura.tick(character, 2_000, %{key(holder) => context})

        assert [%Effects.EnsureCapturedFollower{creature_guid: ^caster}] =
                 Enum.filter(events, &is_struct(&1, Effects.EnsureCapturedFollower))

        assert Aura.next_event_at(ticked) == 4_000
        assert ticked.unit.auras != []
      end
    end

    test "dead, missing, distant and cross-world captures are removed without restoring stale holders" do
      {character, context, caster} = captured(21_827, 10_981)
      [holder] = character.unit.auras

      contexts = [
        %{context | caster_available?: false},
        %{context | caster_position: nil},
        %{context | caster_position: {character.internal.world, 50.001, 0.0, 0.0}},
        %{context | caster_position: {WorldRef.instance(30, Unique.integer()), 0.0, 0.0, 0.0}}
      ]

      for invalid <- contexts do
        {removed, events} = Aura.tick(character, 2_000, %{key(holder) => invalid})
        assert removed.unit.auras == []

        assert %Effects.ForwardScriptSteps{
                 target_guid: caster,
                 source_guid: character.object.guid,
                 world: character.internal.world,
                 steps: [%ScriptStep{command: :despawn, datalong: 1_000}]
               } in events

        refute Enum.any?(events, &is_struct(&1, Effects.EnsureCapturedFollower))
        assert Aura.next_event_at(removed) == nil
      end

      ghost = %{character | player: %{character.player | flags: 0x10}, unit: %{character.unit | health: 1}}
      assert {%{unit: %{auras: []}}, _events} = Aura.tick(ghost, 2_000, %{key(holder) => context})
    end
  end

  describe "release/2" do
    test "delivery, cancellation and logout remove the aura and dismiss its creature after two seconds" do
      {character, _context, caster} = captured(21_863, 10_990)
      {released, events} = CapturedFollower.release(character, 1)
      assert released.unit.auras == []

      assert [%Effects.ForwardScriptSteps{target_guid: ^caster, steps: [%{datalong: 2_000}]}] =
               Enum.filter(events, &is_struct(&1, Effects.ForwardScriptSteps))

      assert CapturedFollower.release(released, 2) == {released, []}
    end
  end

  defp key(holder), do: {holder.spell.id, holder.caster_guid, holder.item_source}

  defp captured(spell_id, entry) do
    player = Unique.integer()
    caster = Guid.from_low_guid(:mob, entry, Unique.integer())
    world = WorldRef.instance(30, Unique.integer())

    character = %Character{
      object: %Object{guid: player},
      player: %Player{},
      unit: %Unit{health: 100, auras: []},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{world: world}
    }

    spell = %Spell{id: spell_id, duration_ms: -1, effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy}]}

    context = %CastContext{
      caster_guid: caster,
      target_guid: player,
      caster_level: 60,
      spell: spell,
      caster_position: {world, 3.0, 0.0, 0.0}
    }

    {character, _events} = Aura.apply_spell(character, context, spell, 0)
    {character, context, caster}
  end
end
