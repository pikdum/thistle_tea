defmodule ThistleTea.Game.Entity.Logic.Aura.PriorityTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.Capacity
  alias ThistleTea.Game.Entity.Logic.Aura.Priority
  alias ThistleTea.Game.Entity.Logic.Aura.UnitSync
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  describe "value/2" do
    test "buffs prefer permanent, external, item, then self-cast sources" do
      base = %Holder{spell: %Spell{id: 1}, caster_guid: 1, expires_at: 10_000}
      assert Priority.value(base, 1) == 0
      assert Priority.value(%{base | cast_item_guid: 12}, 1) == 1
      assert Priority.value(%{base | caster_guid: 2}, 1) == 2
      assert Priority.value(%{base | expires_at: -1}, 1) == 3
    end

    test "family exceptions precede rank and generic aura rules" do
      for {family, mask, priority} <- [
            {8, 0x8, 1},
            {8, 0x100, 2},
            {4, 0x20, 2},
            {7, 0x1000, 2},
            {4, 0x4000, 3},
            {8, 0x200000, 3},
            {7, 0x2000, 3},
            {4, 0x20000, 4},
            {7, 0x8, 4}
          ] do
        holder = negative(:mod_stun)
        holder = %{holder | spell: %{holder.spell | spell_family: family, family_flags_0: mask}}
        assert Priority.value(holder, 1) == priority
      end
    end

    test "rank priorities persist across rank upgrades and triggered casts" do
      for {root, priority} <- [{133, 0}, {118, 0}, {1714, 1}, {172, 2}, {116, 3}, {6136, 4}] do
        holder = negative(:mod_stun)
        holder = %{holder | triggered?: true, spell: %{holder.spell | first_in_chain: root}}
        assert Priority.value(holder, 1) == priority
      end
    end

    test "generic effects use their strongest priority with triggered and channel adjustments" do
      for {type, priority, triggered} <- [
            {:mod_stun, 4, 2},
            {:mod_resistance, 3, 2},
            {:periodic_damage, 1, 0},
            {:dummy, 0, 0},
            {:ranged_attack_power_attacker_bonus, 3, 3}
          ] do
        holder = negative(type)
        assert Priority.value(holder, 1) == priority
        assert Priority.value(%{holder | triggered?: true}, 1) == triggered
      end

      holder = negative(:dummy)
      holder = %{holder | spell: %{holder.spell | attributes: MapSet.new([:channeled])}}
      assert Priority.value(holder, 1) == 1
      holder = %{holder | auras: [%Aura{type: :dummy}, %Aura{type: :mod_stun}]}
      assert Priority.value(holder, 1) == 4
    end
  end

  describe "visible?/2" do
    test "passive area buffs are hidden on their caster but visible on recipients and totems" do
      spell = %Spell{
        id: 1,
        attributes: MapSet.new([:passive]),
        effects: [%Effect{type: :apply_area_aura, aura: :mod_stat}]
      }

      holder = %Holder{spell: spell, caster_guid: 1}
      refute UnitSync.visible?(holder, 1)
      assert UnitSync.visible?(holder, 2)
      assert UnitSync.visible?(%{holder | caster_totem?: true}, 1)
    end

    test "pure persistent area damage is hidden while secondary debuffs require slots" do
      damage = %Effect{type: :persistent_area_aura, aura: :periodic_damage}
      holder = %Holder{spell: %Spell{id: 1, effects: [damage]}}
      refute UnitSync.visible?(holder, 1)
      slow = %{damage | aura: :mod_melee_haste}
      assert UnitSync.visible?(%{holder | spell: %{holder.spell | effects: [damage, slow]}}, 1)
      tick = %{holder.spell | effects: [%{damage | type: :apply_aura}], hidden_aura?: true}
      refute UnitSync.visible?(%{holder | spell: tick}, 1)
    end
  end

  describe "retain/2" do
    test "equal timestamps use spell identifiers deterministically without changing order" do
      holders = for id <- 33..1//-1, do: %Holder{spell: %Spell{id: id}, caster_guid: 1, applied_at: 0}
      retained = Capacity.retain(holders, 1)
      assert Enum.map(retained, & &1.spell.id) == Enum.to_list(33..2//-1)
    end
  end

  defp negative(type), do: %Holder{spell: %Spell{id: 900_000}, negative?: true, auras: [%Aura{type: type}]}
end
