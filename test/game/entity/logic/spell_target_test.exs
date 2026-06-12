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

    test "returns caster cone query for cone spells" do
      spell = aoe_spell(:aoe_enemy_in_cone)

      assert SpellTarget.target_query(spell, %Targets{unit_guid: 2}) == {:caster_cone, 10.0}
    end

    test "returns unit query for direct unit targets" do
      spell = %Spell{id: 133, effects: []}

      assert SpellTarget.target_query(spell, %Targets{unit_guid: 2}) == {:unit, 2}
    end

    test "returns party aoe query for party-around-caster spells" do
      spell = aoe_spell(:party_around_caster)

      assert SpellTarget.target_query(spell, %Targets{}) == {:party_aoe, 10.0}
    end

    test "party aoe takes precedence over a selected unit target" do
      spell = aoe_spell(:party_around_caster)

      assert SpellTarget.target_query(spell, %Targets{unit_guid: 2}) == {:party_aoe, 10.0}
    end

    test "returns none without matching target data" do
      spell = aoe_spell(:aoe_enemy_at_dest)

      assert SpellTarget.target_query(spell, %Targets{}) == :none
    end
  end

  describe "redirect_enemy_trigger/3" do
    test "keeps a self target when the spell does not target enemies" do
      entity = entity_fixture()
      spell = trigger_spell(:target_friend)

      assert SpellTarget.redirect_enemy_trigger(entity, 10, spell) == 10
    end

    test "keeps a non-self target unchanged" do
      entity = entity_fixture(target: 55)
      spell = trigger_spell(:target_enemy)

      assert SpellTarget.redirect_enemy_trigger(entity, 99, spell) == 99
    end

    test "redirects a self-targeted enemy trigger to the channel object" do
      entity = entity_fixture(channel_object: 42, target: 55)
      spell = trigger_spell(:target_enemy)

      assert SpellTarget.redirect_enemy_trigger(entity, 10, spell) == 42
    end

    test "falls back to the current target without a channel object" do
      entity = entity_fixture(target: 55)
      spell = trigger_spell(:target_enemy)

      assert SpellTarget.redirect_enemy_trigger(entity, 10, spell) == 55
    end

    test "drops a self-targeted enemy trigger without any enemy" do
      entity = entity_fixture()
      spell = trigger_spell(:target_enemy)

      assert SpellTarget.redirect_enemy_trigger(entity, 10, spell) == nil
    end
  end

  defp entity_fixture(opts \\ []) do
    %{
      object: %{guid: 10},
      unit: %{
        channel_object: Keyword.get(opts, :channel_object, 0),
        target: Keyword.get(opts, :target, 0)
      }
    }
  end

  defp trigger_spell(target) do
    %Spell{
      id: 7268,
      effects: [
        %Effect{
          type: :school_damage,
          implicit_target_a: target
        }
      ]
    }
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
