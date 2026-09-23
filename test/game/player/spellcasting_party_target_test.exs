defmodule ThistleTea.Game.Player.SpellcastingPartyTargetTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Player.Spellcasting
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  describe "validate_repeat/3" do
    test "rejects a party-only cast before spending resources when its target is invalid" do
      character = %Character{
        object: %Object{guid: 1},
        unit: %Unit{},
        player: %Player{},
        internal: %Internal{}
      }

      spell = %Spell{effects: [%Effect{type: :apply_aura, implicit_target_a: :party_member}]}
      state = %{character: character}

      assert Spellcasting.validate_repeat(state, spell, Target.none()) == {:error, :bad_targets}
      assert Spellcasting.validate_repeat(state, spell, Target.unit(1)) == {:error, :bad_targets}
      assert Spellcasting.validate_repeat(state, spell, Target.unit(2)) == {:error, :bad_targets}
    end
  end
end
