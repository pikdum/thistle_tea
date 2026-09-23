defmodule ThistleTea.Game.Spell.BattlegroundTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Battleground
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Target

  describe "validate/2" do
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
