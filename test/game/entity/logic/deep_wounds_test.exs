defmodule ThistleTea.Game.Entity.Logic.DeepWoundsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellEffect.Script
  alias ThistleTea.Game.Entity.Logic.Stats
  alias ThistleTea.Game.Entity.Logic.Warrior
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  setup [:warrior]

  describe "deep_wounds_tick/2" do
    test "scales all ranks from average damage including attack power", %{warrior: warrior} do
      assert warrior.unit.min_damage == 100
      assert warrior.unit.max_damage == 140

      for {id, expected} <- [{12_162, 6}, {12_850, 12}, {12_868, 18}] do
        assert Warrior.deep_wounds_tick(warrior, spell(id)) == expected
      end

      assert Warrior.deep_wounds_tick(warrior, spell(1)) == nil
    end

    test "includes applicable flat and percentage weapon bonuses", %{warrior: warrior} do
      holder = %Holder{
        spell: %Spell{id: 9},
        auras: [
          %Aura{type: :mod_damage_done, amount: 10, misc_value: 1},
          %Aura{type: :mod_damage_percent_done, amount: 20, misc_value: 1}
        ]
      }

      warrior = %{warrior | unit: %{warrior.unit | auras: [holder]}}
      assert Warrior.deep_wounds_tick(warrior, spell(12_868)) == 23
    end

    test "uses an earlier offhand swing with its normal damage penalty", %{warrior: warrior} do
      blackboard = %Blackboard{}
      blackboard = %{blackboard | combat: %{blackboard.combat | next_attack_at: 4_000, next_offhand_attack_at: 3_000}}
      warrior = %{warrior | internal: %{warrior.internal | blackboard: blackboard}}
      assert Warrior.deep_wounds_tick(warrior, spell(12_868)) == 3

      broken = %{warrior | player: %{warrior.player | broken_equipment: [:offhand]}}
      assert Warrior.deep_wounds_tick(broken, spell(12_868)) == 18
    end

    test "uses mainhand when timers are tied or it is due first", %{warrior: warrior} do
      for offhand_at <- [4_000, 5_000] do
        blackboard = %Blackboard{}

        blackboard = %{
          blackboard
          | combat: %{blackboard.combat | next_attack_at: 4_000, next_offhand_attack_at: offhand_at}
        }

        warrior = %{warrior | internal: %{warrior.internal | blackboard: blackboard}}
        assert Warrior.deep_wounds_tick(warrior, spell(12_868)) == 18
      end
    end
  end

  describe "apply/5" do
    test "dispatches the snapshotted bleed through the source owner", %{warrior: warrior} do
      spell = spell(12_868)
      context = CastContext.from_caster(warrior, spell, 2)
      changed = %{warrior | unit: %{warrior.unit | attack_power: 1_400} |> Stats.recompute()}
      assert Warrior.deep_wounds_tick(changed, spell) > context.deep_wounds_tick
      target = %{warrior | object: %Object{guid: 2}}

      assert {^target,
              [
                %Effects.TriggerSpell{
                  source_guid: 1,
                  target_guid: 2,
                  spell_id: 12_721,
                  amount: 18,
                  slot: 0,
                  resolve_targets?: true,
                  requires_living_target?: true,
                  triggering_spell_id: 12_868
                }
              ]} = Script.apply(target, context, spell, hd(spell.effects), 0)
    end

    test "rejects missing snapshots and dead recipients", %{warrior: warrior} do
      spell = spell(12_868)
      dead = %{warrior | unit: %{warrior.unit | health: 0}}
      context = CastContext.from_caster(warrior, spell, 1)
      assert {^dead, []} = Script.apply(dead, context, spell, hd(spell.effects), 0)
      assert {^warrior, []} = Script.apply(warrior, %CastContext{}, spell, hd(spell.effects), 0)
    end
  end

  defp spell(id), do: %Spell{id: id, effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :single_enemy}]}

  defp warrior(_context) do
    weapon = %{class: 2, subclass: 7, inventory_type: 13}

    unit =
      %Unit{
        level: 60,
        health: 1_000,
        max_health: 1_000,
        auras: [],
        attack_power: 140,
        base_min_damage: 80.0,
        base_max_damage: 120.0,
        base_melee_attack_time: 2_000,
        base_offhand_min_damage: 20.0,
        base_offhand_max_damage: 40.0,
        base_offhand_attack_time: 2_000,
        mainhand_weapon: weapon,
        offhand_weapon: weapon
      }
      |> Stats.recompute()

    %{warrior: %Character{object: %Object{guid: 1}, unit: unit, player: %Player{}, internal: %Internal{}}}
  end
end
