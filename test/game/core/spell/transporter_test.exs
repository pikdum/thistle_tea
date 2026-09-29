defmodule ThistleTea.Game.Core.Spell.TransporterTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Effects.RandomChoice
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect

  setup [:traveler]

  describe "receive/4" do
    test "Gadgetzan selects a normal arrival, a malfunction arrival, or a fall", %{traveler: traveler, cast: cast} do
      spell = dummy(23_453)
      assert {^traveler, [%RandomChoice{} = choice]} = SpellEffect.receive(traveler, cast, spell, 0)
      assert RandomChoice.total_weight(choice) == 4

      for {roll, id} <- [{1, 23_441}, {2, 23_441}, {3, 23_446}] do
        assert [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, spell_id: ^id, cast_item_guid: 42}] =
                 RandomChoice.select(choice, roll)
      end

      assert [
               %Effects.TeleportToWorld{
                 world: 1,
                 position: {-7341.38, -3908.11, 150.7},
                 orientation: 0.51
               }
             ] = RandomChoice.select(choice, 4)
    end

    test "Gadgetzan arrival can transform, apply Evil Twin, or leave the traveler unchanged", context do
      {_, [%RandomChoice{} = choice]} = SpellEffect.receive(context.traveler, context.cast, dummy(23_448), 0)
      assert RandomChoice.total_weight(choice) == 6
      assert [%Effects.TriggerSpell{spell_id: 23_444}] = RandomChoice.select(choice, 1)

      for roll <- 2..5 do
        assert [%Effects.TriggerSpell{spell_id: 23_445}] = RandomChoice.select(choice, roll)
      end

      assert RandomChoice.select(choice, 6) == []
    end

    test "Everlook always teleports and rolls its independent mishap", %{traveler: traveler, cast: cast} do
      spell = %Spell{
        id: 23_442,
        script_name: "spell_everlook_transporter",
        effects: [%Effect{index: 0, type: :teleport_units, implicit_target_a: :caster}]
      }

      assert {^traveler, [%Effects.TeleportToSpellTarget{spell_id: 23_442}, %RandomChoice{} = choice]} =
               SpellEffect.receive(traveler, cast, spell, 0)

      outcomes =
        for roll <- 1..12 do
          case RandomChoice.select(choice, roll) do
            [] -> :normal
            [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, cast_item_guid: 42, spell_id: id}] -> id
          end
        end

      assert Enum.frequencies(outcomes) == %{:normal => 7, 23_445 => 3, 23_449 => 2}

      assert {^traveler, [%Effects.TeleportToSpellTarget{spell_id: 23_442}]} =
               SpellEffect.receive(traveler, cast, %{spell | script_name: nil}, 0)
    end

    test "dummy outcomes run once and ignore dead travelers", %{traveler: traveler, cast: cast} do
      for id <- [23_448, 23_453] do
        spell = dummy(id)
        second = %{spell | effects: [%{hd(spell.effects) | index: 1}]}
        assert {^traveler, []} = SpellEffect.receive(traveler, cast, second, 0)
        dead = %{traveler | unit: %{traveler.unit | health: 0}}
        assert {^dead, []} = SpellEffect.receive(dead, cast, spell, 0)
      end
    end
  end

  defp dummy(id), do: %Spell{id: id, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :caster}]}

  defp traveler(_context) do
    %{
      traveler: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, auras: []},
        player: %Player{},
        internal: %Internal{}
      },
      cast: %CastContext{caster_guid: 1, caster_level: 60, target_guid: 1, cast_item_guid: 42}
    }
  end
end
