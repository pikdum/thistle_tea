defmodule ThistleTea.Game.World.Loader.ItemEnchantmentIntegrationTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.World.Loader.ItemEnchantment

  @moduletag :dbc_db
  @moduletag :vmangos_db

  setup do
    ItemEnchantment.load_all()
    :ok
  end

  test "loads fishing bonuses and VMangos lure durations" do
    assert ItemEnchantment.skill_bonus(263, 356) == 25
    assert ItemEnchantment.skill_bonus(265, 356) == 75

    effect = %Effect{base_points: 0, die_sides: 1}
    assert ItemEnchantment.duration_ms(8087, effect) == 600_000
    assert ItemEnchantment.duration_ms(8089, effect) == 300_000
  end
end
