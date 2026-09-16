defmodule ThistleTea.Game.Entity.Logic.Aura.PowerCostSyncTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.PowerCostSync
  alias ThistleTea.Game.Entity.Logic.Resources
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell

  setup [:mana_user]

  describe "sync/1" do
    test "serializes signed reductions and fractional multipliers by school", %{entity: entity} do
      unit = PowerCostSync.sync(entity.unit)

      assert for(<<value::little-signed-size(32) <- unit.power_cost_modifier>>, do: value) ==
               [0, -100, -80, -100, -100, -100, -100]

      assert for(<<value::little-float-size(32) <- unit.power_cost_multiplier>>, do: value) ==
               [0.0, 0.0, 0.5, 0.0, 0.0, 0.0, 0.0]

      assert PowerCostSync.sync(unit) == unit

      own_fields = Unit.to_list(unit, :self)
      flat = List.keyfind(own_fields, :power_cost_modifier, 0)
      percent = List.keyfind(own_fields, :power_cost_multiplier, 0)
      assert UpdateObject.field(flat) == unit.power_cost_modifier
      assert UpdateObject.field(percent) == unit.power_cost_multiplier
      refute List.keymember?(Unit.to_list(unit, :other), :power_cost_modifier, 0)
      refute List.keymember?(Unit.to_list(unit, :other), :power_cost_multiplier, 0)
    end

    test "cancellation and expiry rebuild costs and explicitly clear client fields", %{entity: entity} do
      {entity, _events} = Aura.cancel_spell(entity, 1, 1_000)
      assert Resources.power_cost(entity, spell(:fire)) == 330
      assert entity.internal.broadcast_update?

      {entity, _events} = Aura.expire_due(entity, 10_000)
      assert Resources.power_cost(entity, spell(:fire)) == 200
      assert entity.unit.power_cost_modifier == <<0::size(224)>>
      assert entity.unit.power_cost_multiplier == <<0::size(224)>>
    end

    test "empty or missing holders clear previous projections", %{entity: entity} do
      unit = PowerCostSync.sync(entity.unit)

      for holders <- [[], nil] do
        cleared = PowerCostSync.sync(%{unit | auras: holders})
        assert cleared.power_cost_modifier == <<0::size(224)>>
        assert cleared.power_cost_multiplier == <<0::size(224)>>
      end
    end
  end

  describe "power_cost/2" do
    test "adds stacked flat modifiers before school percentages", %{entity: entity} do
      assert Resources.power_cost(entity, spell(:fire)) == 180
      assert Resources.power_cost(entity, spell(:frost)) == 100
      assert Resources.power_cost(entity, spell(:physical)) == 200
    end

    test "applies spell-family modifiers after flat school modifiers", %{entity: entity} do
      talent = %Holder{
        spell: %Spell{id: 4, spell_family: 8},
        auras: [%AuraData{type: :add_pct_modifier, amount: -50, class_mask: 1, misc_value: 14}]
      }

      entity = %{entity | unit: %{entity.unit | auras: [talent | entity.unit.auras]}}
      affected = %{spell(:fire) | spell_family: 8, family_flags_0: 1}
      assert Resources.power_cost(entity, affected) == 90
      assert Resources.power_cost(entity, %{affected | family_flags_0: 2}) == 180
    end

    test "includes percent of base mana before the flat reduction", %{entity: entity} do
      spell = %{spell(:frost) | mana_cost: 20, mana_cost_percent: 10}
      assert Resources.power_cost(entity, spell) == 20
    end

    test "free spells neither spend mana nor start the five-second rule", %{entity: entity} do
      spell = %{spell(:frost) | mana_cost: 50}
      assert Resources.power_cost(entity, spell) == 0
      assert Resources.spend_power(entity, spell, 1_000) == entity
    end

    test "payment uses the modified amount and records mana use", %{entity: entity} do
      result = Resources.spend_power(entity, spell(:fire), 1_000)
      assert result.unit.power1 == 820
      assert result.internal.last_mana_use_at == 1_000
      assert Resources.can_pay_cost?(result, 0, 180)
      refute Resources.can_pay_cost?(%{result | unit: %{result.unit | power1: 179}}, 0, 180)
    end

    test "all-power spells bypass reductions and increases", %{entity: entity} do
      spell = %{spell(:fire) | attributes: MapSet.new([:use_all_mana])}
      assert Resources.power_cost(entity, spell) == 1_000
      assert Resources.spend_power(entity, spell, 1_000).unit.power1 == 0
      assert Resources.power_cost(entity, %{spell | power_type: -2}) == 500
    end

    test "school reductions apply to energy without marking mana use", %{entity: entity} do
      spell = %{spell(:frost) | mana_cost: 150, power_type: 3}
      result = Resources.spend_power(entity, spell, 1_000)
      assert result.unit.power4 == 50
      assert result.internal.last_mana_use_at == nil
    end
  end

  defp mana_user(_context) do
    holders = [
      holder(1, :mod_power_cost_school, -100, 126),
      %{holder(2, :mod_power_cost_school, 10, 4) | stacks: 2},
      holder(3, :mod_power_cost_school_pct, 50, 4)
    ]

    entity = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{
        health: 500,
        max_health: 500,
        power1: 1_000,
        max_power1: 2_000,
        base_mana: 1_000,
        power4: 100,
        auras: holders
      },
      internal: %Internal{}
    }

    %{entity: entity}
  end

  defp holder(id, type, amount, mask) do
    %Holder{
      spell: %Spell{id: id},
      expires_at: 10_000,
      auras: [%AuraData{type: type, amount: amount, misc_value: mask}]
    }
  end

  defp spell(school), do: %Spell{school: school, mana_cost: 200, power_type: 0}
end
