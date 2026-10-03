defmodule ThistleTea.Game.Core.Spell.HolidayTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Effects.RandomChoice
  alias ThistleTea.Game.Core.Effects.WhenGrouped
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.CastContext
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.SpellEffect

  setup [:player]

  describe "receive/4" do
    test "Trick or Treat marks the player and has them trick or treat themselves", %{player: player} do
      cast = from(99, :mob)

      assert {_, [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, spell_id: 24_755}, %RandomChoice{} = choice]} =
               SpellEffect.receive(player, cast, script(24_751), 0)

      assert spell_ids(choice) == [24_714, 24_715]
      assert {_, []} = SpellEffect.receive(mob(), cast, script(24_751), 0)
    end

    test "Trick dresses the trickster in a random costume for their gender", %{player: player} do
      {_, [choice]} = SpellEffect.receive(player, from(1, :player), script(24_714), 0)
      assert spell_ids(choice) == [24_708, 24_711, 24_712, 24_735, 24_723, 24_732, 24_740, 24_753]
      assert Enum.all?(sources(choice), &(&1 == {1, 1}))

      {_, [choice]} = SpellEffect.receive(female(player), from(1, :player), script(24_714), 0)
      assert spell_ids(choice) == [24_709, 24_710, 24_713, 24_736, 24_723, 24_732, 24_740, 24_753]
    end

    test "Hallowed Wands costume an out-of-combat player from the wand holder", %{player: player} do
      for {wand, male, female} <- [
            {24_717, 24_708, 24_709},
            {24_718, 24_711, 24_710},
            {24_719, 24_712, 24_713},
            {24_737, 24_735, 24_736}
          ] do
        assert {_, [%Effects.TriggerSpell{source_guid: 7, target_guid: 1, spell_id: ^male}]} =
                 SpellEffect.receive(player, from(7, :player), script(wand, :target_ally), 0)

        assert {_, [%Effects.TriggerSpell{spell_id: ^female}]} =
                 SpellEffect.receive(female(player), from(7, :player), script(wand, :target_ally), 0)
      end

      {_, [choice]} = SpellEffect.receive(player, from(7, :player), script(24_720, :target_ally), 0)
      assert spell_ids(choice) == [24_708, 24_711, 24_712, 24_723, 24_732, 24_735, 24_740]
      assert Enum.all?(sources(choice), &(&1 == {7, 1}))
    end

    test "Hallowed Wands do nothing in combat or on creatures", %{player: player} do
      fighting = %{player | internal: %{player.internal | in_combat: true}}

      for wand <- [24_717, 24_718, 24_719, 24_720, 24_737] do
        assert {_, []} = SpellEffect.receive(fighting, from(7, :player), script(wand, :target_ally), 0)
        assert {_, []} = SpellEffect.receive(mob(), from(7, :player), script(wand, :target_ally), 0)
      end
    end

    test "Hallow's End Candy and Bag of Candies have the eater cast one of their spells", %{player: player} do
      {_, [choice]} = SpellEffect.receive(player, from(1, :player), dummy(24_930, :caster), 0)
      assert spell_ids(choice) == [24_924, 24_925, 24_926, 24_927]
      assert Enum.all?(sources(choice), &(&1 == {1, 1}))

      {_, [choice]} = SpellEffect.receive(player, from(1, :player), script(26_678, :caster), 0)
      assert spell_ids(choice) == [26_668, 26_670, 26_671, 26_672, 26_673, 26_674, 26_675, 26_676]
    end

    test "a snowball knocks down a grouped player who has not grown resistant", %{player: player} do
      assert {_, [%WhenGrouped{guids: [7, 1], effects: [%Effects.TriggerSpell{source_guid: 1, spell_id: 21_167}]}]} =
               SpellEffect.receive(player, from(7, :player), dummy(21_343), 0)

      resistant = %{player | unit: %{player.unit | auras: [%Holder{spell: %Spell{id: 21_354}, auras: []}]}}
      assert {_, []} = SpellEffect.receive(resistant, from(7, :player), dummy(21_343), 0)
      assert {_, []} = SpellEffect.receive(player, from(7, :mob), dummy(21_343), 0)
      assert {_, []} = SpellEffect.receive(player, from(1, :player), dummy(21_343), 0)
    end

    test "mistletoe makes its target respond and Greatfather Winter's gives a sprig", %{player: player} do
      assert {_, [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, spell_id: 26_005}]} =
               SpellEffect.receive(player, from(7, :player), script(26_004, :target_ally), 0)

      {_, [choice]} = SpellEffect.receive(player, from(9, :mob), script(26_218), 0)
      assert spell_ids(choice) == [26_206, 26_207]
      assert Enum.all?(sources(choice), &(&1 == {9, 1}))
    end

    test "the Winter Wondervolt swaps the costume of a player at its heart", %{player: player} do
      dressed = %{player | unit: %{player.unit | auras: [%Holder{spell: %Spell{id: 26_272}, auras: []}]}}
      trap = %{from(5, nil) | caster_position: {0, 10.5, 0.0, 0.0}}

      assert {%Character{unit: %{auras: []}}, events} = SpellEffect.receive(dressed, trap, script(26_275), 0)
      assert [choice] = Enum.filter(events, &is_struct(&1, RandomChoice))
      assert spell_ids(choice) == [26_272, 26_157, 26_273, 26_274]
      assert Enum.all?(sources(choice), &(&1 == {1, 1}))

      far = %{trap | caster_position: {0, 11.5, 0.0, 0.0}}
      assert {_, [_ | _]} = SpellEffect.receive(put_in(dressed.unit.bounding_radius, 0.6), far, script(26_275), 0)
      assert {^dressed, []} = SpellEffect.receive(dressed, far, script(26_275), 0)
    end
  end

  defp spell_ids(%RandomChoice{choices: choices}),
    do: Enum.map(choices, fn {1, [%Effects.TriggerSpell{spell_id: id}]} -> id end)

  defp sources(%RandomChoice{choices: choices}),
    do:
      Enum.map(choices, fn {1, [%Effects.TriggerSpell{source_guid: source, target_guid: target}]} ->
        {source, target}
      end)

  defp script(id, target \\ :any_unit), do: spell(id, :script_effect, target)
  defp dummy(id, target \\ :any_unit), do: spell(id, :dummy, target)
  defp spell(id, type, target), do: %Spell{id: id, effects: [%Effect{index: 0, type: type, implicit_target_a: target}]}

  defp from(guid, type), do: %CastContext{caster_guid: guid, caster_level: 60, caster_type: type, target_guid: 1}

  defp female(%Character{} = player), do: %{player | unit: %{player.unit | gender: 1}}

  defp mob do
    %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: []},
      internal: %Internal{}
    }
  end

  defp player(_context) do
    %{
      player: %Character{
        object: %Object{guid: 1},
        unit: %Unit{health: 1_000, max_health: 1_000, level: 60, gender: 0, auras: []},
        player: %Player{},
        movement_block: %MovementBlock{position: {10.0, 0.0, 0.0, 0.0}},
        internal: %Internal{}
      }
    }
  end
end
