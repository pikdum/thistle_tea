defmodule ThistleTea.Game.World.Loader.SpellObjectActionsDbcTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader

  @moduletag :dbc_db

  describe "load/1" do
    test "keeps opening distinct from scripted activation" do
      assert [%Effect{type: :open_lock_item, implicit_target_a: :game_object} | _] = SpellLoader.load(3_366).effects
      assert [%Effect{type: :open_lock_item} | _] = SpellLoader.load(6_250).effects

      assert [%Effect{type: :activate_object, misc_value: 1, implicit_target_a: :game_object_near_caster} | _] =
               SpellLoader.load(18_655).effects
    end

    test "decodes source and destination object areas" do
      assert [%Effect{type: :activate_object, misc_value: 15, implicit_target_b: :game_objects_at_source} | _] =
               SpellLoader.load(23_479).effects

      assert [%Effect{type: :activate_object, misc_value: 8, implicit_target_b: :game_objects_at_destination} | _] =
               SpellLoader.load(24_083).effects
    end
  end
end
