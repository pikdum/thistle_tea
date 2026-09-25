defmodule ThistleTea.Game.World.Loader.ControlledPetDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell

  @moduletag :dbc_db

  describe "load/1" do
    test "maps permanent creature pets and timed elementals to controlled summons" do
      for {id, entry, duration, target} <- [
            {3612, 698, -1, :caster_destination},
            {3621, 756, -1, :minion_position},
            {11_939, 12_922, -1, :minion_position},
            {22_865, 14_385, -1, :minion_position},
            {513, 329, 60_000, :caster_destination},
            {895, 575, 60_000, :caster_destination}
          ] do
        spell = Spell.load(id)
        assert [%Effect{type: :summon, misc_value: ^entry, implicit_target_a: ^target}] = spell.effects
        assert spell.duration_ms == duration
      end
    end
  end
end
