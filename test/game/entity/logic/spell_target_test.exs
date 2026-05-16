defmodule ThistleTea.Game.Entity.Logic.SpellTargetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Targets

  describe "target_query/2" do
    test "returns caster aoe query for caster aoe spells" do
      spell = aoe_spell(:aoe_enemy_at_caster)

      assert SpellTarget.target_query(spell, %Targets{unit_guid: 2}) == {:caster_aoe, 10.0}
    end

    test "returns targeted aoe query for ground-target spells" do
      spell = aoe_spell(:aoe_enemy_at_dest)
      targets = %Targets{destination_location: {1.0, 2.0, 3.0}}

      assert SpellTarget.target_query(spell, targets) == {:targeted_aoe, {1.0, 2.0, 3.0}, 10.0}
    end

    test "returns unit query for direct unit targets" do
      spell = %Spell{id: 133, effects: []}

      assert SpellTarget.target_query(spell, %Targets{unit_guid: 2}) == {:unit, 2}
    end

    test "returns none without matching target data" do
      spell = aoe_spell(:aoe_enemy_at_dest)

      assert SpellTarget.target_query(spell, %Targets{}) == :none
    end
  end

  defp aoe_spell(target) do
    %Spell{
      id: 122,
      effects: [
        %Effect{
          implicit_target_a: target,
          radius_yards: 10.0
        }
      ]
    }
  end
end
