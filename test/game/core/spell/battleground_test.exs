defmodule ThistleTea.Game.Core.Spell.BattlegroundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Battleground
  alias ThistleTea.Game.Core.Spell.CastValidation
  alias ThistleTea.Game.Core.Spell.Target

  describe "validate/2" do
    test "beacon planting requires an active match and the item's team" do
      for {ids, team, opponent} <- [
            {[21_355, 21_370, 21_371], :horde, :alliance},
            {[21_728, 21_729, 21_730], :alliance, :horde}
          ],
          id <- ids do
        spell = %Spell{id: id}
        assert Battleground.restricted?(spell)
        assert Battleground.validate(spell, %{map_id: 30, phase: :active, team: team}) == :ok

        for context <- [
              nil,
              %{map_id: 30, phase: :active, team: opponent},
              %{map_id: 529, phase: :active, team: team},
              %{map_id: 30, phase: :countdown, team: team},
              %{map_id: 30, phase: {:ended, team}, team: team}
            ] do
          assert Battleground.validate(spell, context) == {:error, :requires_area}
        end
      end
    end

    test "requires actual membership for battleground-only spells" do
      spell = %Spell{id: 23_034, attributes: MapSet.new([:only_battlegrounds])}
      assert Battleground.restricted?(spell)
      assert Battleground.validate(spell, nil) == {:error, :only_battlegrounds}
      assert Battleground.validate(spell, %{map_id: 529, phase: :countdown}) == :ok

      caster = %Character{object: %Object{guid: 1}, unit: %Unit{health: 100}, internal: %Internal{}}
      assert CastValidation.validate(caster, spell, Target.self(1), %{}, 0) == {:error, :only_battlegrounds}
      assert Battleground.validate(%Spell{id: 133}, nil) == :ok
    end

    test "Alterac standards and recall wait for an active Alterac match" do
      for id <- [22_563, 22_564, 23_538, 23_539] do
        spell = %Spell{id: id}
        assert Battleground.restricted?(spell)
        assert Battleground.validate(spell, nil) == {:error, :requires_area}
        assert Battleground.validate(spell, %{map_id: 529, phase: :active}) == {:error, :requires_area}
        assert Battleground.validate(spell, %{map_id: 30, phase: :countdown}) == {:error, :requires_area}
        assert Battleground.validate(spell, %{map_id: 30, phase: :active}) == :ok
      end
    end
  end
end
