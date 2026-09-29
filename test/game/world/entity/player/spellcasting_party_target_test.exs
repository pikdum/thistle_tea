defmodule ThistleTea.Game.World.Entity.Player.SpellcastingPartyTargetTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Effect
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.World.Entity.Player.Spellcasting

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
