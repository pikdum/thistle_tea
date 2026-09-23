defmodule ThistleTea.Game.Entity.Logic.SpellTargetTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Logic.SpellTarget
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Target

  describe "target_query/2" do
    test "returns caster aoe query for caster aoe spells" do
      spell = aoe_spell(:aoe_enemy_at_caster)

      assert SpellTarget.target_query(spell, Target.unit(2)) == {:caster_aoe, 10.0}
    end

    test "returns targeted aoe query for ground-target spells" do
      spell = aoe_spell(:aoe_enemy_at_dest)
      targets = Target.at({1.0, 2.0, 3.0})

      assert SpellTarget.target_query(spell, targets) == {:targeted_aoe, {1.0, 2.0, 3.0}, 10.0}
    end

    test "returns caster cone query for cone spells" do
      spell = aoe_spell(:aoe_enemy_in_cone)

      assert SpellTarget.target_query(spell, Target.unit(2)) == {:caster_cone, 10.0}
    end

    test "returns unit query for direct unit targets" do
      spell = %Spell{id: 133, effects: []}

      assert SpellTarget.target_query(spell, Target.unit(2)) == {:unit, 2}
    end

    test "returns party aoe query for party-around-caster spells" do
      spell = aoe_spell(:party_around_caster)

      assert SpellTarget.target_query(spell, Target.none()) == {:party_aoe, 10.0}
    end

    test "party aoe takes precedence over a selected unit target" do
      spell = aoe_spell(:party_around_caster)

      assert SpellTarget.target_query(spell, Target.unit(2)) == {:party_aoe, 10.0}
    end

    test "targeted party buffs use the selected unit as their center" do
      spell = aoe_spell(:party_around_target)

      assert SpellTarget.target_query(spell, Target.unit(2)) == {:target_party_aoe, 2, 10.0, 0}
      assert SpellTarget.target_query(spell, Target.none()) == :none
      assert SpellTarget.area_targeted?(spell)
      assert Spell.requires_friendly_target?(spell)
    end

    test "party-only unit spells retain their membership requirement" do
      spell = aoe_spell(:party_member)

      assert SpellTarget.target_query(spell, Target.unit(2)) == {:party_unit, 2}
      assert SpellTarget.target_query(spell, Target.none()) == :none
      assert Spell.requires_friendly_target?(spell)
    end

    test "master-targeted pet spells ignore an explicit selected unit" do
      spell = %Spell{
        effects: [
          %Effect{type: :apply_aura, implicit_target_a: :caster_master},
          %Effect{type: :instakill, implicit_target_a: :caster}
        ]
      }

      assert SpellTarget.target_query(spell, Target.none()) == :caster_master
      assert SpellTarget.target_query(spell, Target.unit(7)) == :caster_master
    end

    test "mixed enemy and master spells retain both recipients" do
      spell = %Spell{
        effects: [
          %Effect{type: :school_damage, implicit_target_a: :target_enemy},
          %Effect{type: :apply_aura, implicit_target_a: :target_enemy, implicit_target_b: :caster_master}
        ]
      }

      assert SpellTarget.target_query(spell, Target.unit(7)) == {:unit_and_master, 7}
    end

    test "returns none without matching target data" do
      spell = aoe_spell(:aoe_enemy_at_dest)

      assert SpellTarget.target_query(spell, Target.none()) == :none
    end

    test "treats caster-position destination aoe as a caster aoe" do
      spell = %Spell{
        id: 5857,
        effects: [
          %Effect{
            type: :school_damage,
            implicit_target_a: :caster_destination,
            implicit_target_b: :aoe_enemy_at_dest,
            radius_yards: 10.0
          }
        ]
      }

      assert SpellTarget.target_query(spell, Target.unit(2)) == {:caster_aoe, 10.0}
      assert SpellTarget.target_query(spell, Target.none()) == {:caster_aoe, 10.0}
    end
  end

  describe "area_targeted?/1" do
    test "recognizes DBC area targets independently of packet targets" do
      area = %Spell{effects: [%Effect{implicit_target_a: :aoe_enemy_at_caster}]}
      direct = %Spell{effects: [%Effect{implicit_target_a: :target_enemy}]}

      assert SpellTarget.area_targeted?(area)
      refute SpellTarget.area_targeted?(direct)
    end
  end

  describe "redirect_trigger_target/3" do
    test "keeps a self target when the spell does not target enemies" do
      entity = entity_fixture()
      spell = trigger_spell(:target_friend)

      assert SpellTarget.redirect_trigger_target(entity, 10, spell) == 10
    end

    test "keeps a non-self target unchanged" do
      entity = entity_fixture(target: 55)
      spell = trigger_spell(:target_enemy)

      assert SpellTarget.redirect_trigger_target(entity, 99, spell) == 99
    end

    test "redirects a victim-proposed proc to its DBC caster target" do
      entity = entity_fixture(target: 55)
      spell = trigger_spell(:caster)

      assert SpellTarget.redirect_trigger_target(entity, 99, spell) == 10
    end

    test "redirects a self-targeted enemy trigger to the channel object" do
      entity = entity_fixture(channel_object: 42, target: 55)
      spell = trigger_spell(:target_enemy)

      assert SpellTarget.redirect_trigger_target(entity, 10, spell) == 42
    end

    test "falls back to the current target without a channel object" do
      entity = entity_fixture(target: 55)
      spell = trigger_spell(:target_enemy)

      assert SpellTarget.redirect_trigger_target(entity, 10, spell) == 55
    end

    test "drops a self-targeted enemy trigger without any enemy" do
      entity = entity_fixture()
      spell = trigger_spell(:target_enemy)

      assert SpellTarget.redirect_trigger_target(entity, 10, spell) == nil
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
