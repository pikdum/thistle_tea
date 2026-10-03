defmodule ThistleTea.Game.Core.Spell.SpellEffect.DreamDragonTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Semantics
  alias ThistleTea.Game.Core.Spell.SpellEffect
  alias ThistleTea.Game.Core.Spell.SpellEffect.Script
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Test.Unique

  setup [:player]

  describe "apply/5" do
    test "Aura of Nature stuns players carrying either dragon mark", %{player: player} do
      for {aura_id, mark_id, stun_id} <- [{25_044, 25_040, 25_043}, {23_185, 23_182, 23_186}] do
        marked = with_holders(player, [holder(mark_id, :dummy)])

        assert {_player, [%Effects.TriggerSpell{source_guid: guid, target_guid: guid, spell_id: ^stun_id}]} =
                 Script.apply(marked, %CastContext{caster_guid: 99}, dummy(aura_id), dummy_effect(), 0)

        assert guid == player.object.guid
      end
    end

    test "Aura of Nature only draws unmarked players out of stealth", %{player: player} do
      stealthed = with_holders(player, [holder(1784, :mod_stealth)])

      assert {%Character{unit: %Unit{auras: []}}, events} =
               Script.apply(stealthed, %CastContext{caster_guid: 99}, dummy(25_044), dummy_effect(), 0)

      refute Enum.any?(events, &match?(%Effects.TriggerSpell{}, &1))
    end
  end

  describe "receive/4" do
    test "a corpse keeps a mark that persists through death and sheds any other aura", %{player: player} do
      corpse = %{player | unit: %{player.unit | health: 0}}
      context = %CastContext{caster_guid: player.object.guid, caster_level: 60}

      for {attributes, kept?} <- [
            {[:death_persistent], true},
            {[:allow_dead_target], true},
            {[], false}
          ] do
        spell = mark(attributes)
        {after_receive, _events} = SpellEffect.receive(corpse, context, spell, 1_000)
        assert Aura.has_spell?(after_receive, 25_040) == kept?
      end
    end
  end

  describe "death" do
    test "dragon marks leave their lasting mark on the corpse", %{player: player} do
      for {aura_id, mark_id} <- [{25_042, 25_040}, {23_183, 23_182}, {24_906, 24_904}] do
        dead = player |> with_holders([holder(aura_id, :dummy)]) |> Entity.take_damage(1_000, 500)

        assert dead.unit.auras == []

        assert Enum.any?(
                 dead.internal.events,
                 &match?(%Effects.TriggerSpell{spell_id: ^mark_id, triggering_spell_id: ^aura_id}, &1)
               )
      end
    end
  end

  defp player(_context) do
    guid = Unique.integer()

    %{
      player: %Character{
        object: %Object{guid: guid},
        unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
        player: %Player{},
        internal: %Internal{world: %WorldRef{map_id: 0}},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp with_holders(%Character{} = player, holders), do: %{player | unit: %{player.unit | auras: holders}}

  defp holder(spell_id, type) do
    %Holder{spell: %Spell{id: spell_id}, caster_guid: 99, caster_level: 63, auras: [%Aura{type: type}]}
  end

  defp mark(attributes) do
    Semantics.compile(%Spell{
      id: 25_040,
      name: "Mark of Nature",
      school: :nature,
      duration_ms: 900_000,
      attributes: MapSet.new(attributes),
      effects: [%Effect{index: 0, type: :apply_aura, aura: :dummy, base_points: 0, die_sides: 0, misc_value: 0}]
    })
  end

  defp dummy(id), do: %Spell{id: id, effects: [dummy_effect()]}
  defp dummy_effect, do: %Effect{index: 0, type: :dummy}
end
