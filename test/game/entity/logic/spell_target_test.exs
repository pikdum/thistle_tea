defmodule ThistleTea.Game.Entity.Logic.SpellTargetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Targets

  describe "resolve/3" do
    test "returns direct unit targets without world lookup" do
      caster = %{object: %{guid: 1}}
      spell = %Spell{id: 133, effects: []}
      targets = %Targets{unit_guid: 2}

      assert SpellTarget.resolve(caster, spell, targets) == [2]
    end
  end
end
