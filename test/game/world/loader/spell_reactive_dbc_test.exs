defmodule ThistleTea.Game.World.Loader.SpellReactiveDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "all reactive ability ranks use the correct client aura state" do
      for id <- [1495, 14_269, 14_270, 14_271, 14_251, 6572, 6574, 7379, 11_600, 11_601, 25_288] do
        spell = SpellLoader.load(id)
        assert spell.caster_aura_state == 1, "expected defense state for #{spell.name} (#{id})"
      end

      for id <- [19_306, 20_909, 20_910] do
        assert SpellLoader.load(id).caster_aura_state == 7
      end
    end
  end
end
