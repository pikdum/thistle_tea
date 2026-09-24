defmodule ThistleTea.Game.Entity.Logic.ShieldBlockTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  setup [:character]

  describe "block_chance/1" do
    test "projects aura bonuses and removes them with the shield", %{character: character} do
      {buffed, _} = Aura.apply_spell(character, 1, 60, bonus_spell(2565, :mod_block_percent, 75), 0)
      assert CombatRatings.block_chance(buffed) == 80.0
      assert buffed.player.block_percentage == 80.0
      {cancelled, _} = Aura.cancel_spell(buffed, 2565, 1_000)
      assert cancelled.player.block_percentage == 5.0

      unshielded = %{buffed | unit: %{buffed.unit | equipment_bonuses: %{}}} |> CombatRatings.sync()
      assert unshielded.player.block_percentage == 0.0
      assert CombatRatings.block_chance(unshielded) == 0.0
      gear = %{buffed | unit: %{buffed.unit | equipment_bonuses: %{shields: 1, block_chance: 3}}}
      assert CombatRatings.block_chance(gear) == 83.0
      gear = %{gear | unit: %{gear.unit | equipment_bonuses: %{shields: 0, block_chance: 3}}}
      assert CombatRatings.block_chance(gear) == 0.0

      for level <- [50, 60], roll <- [1_200, 5_000] do
        attack = %{caster_level: level, caster_player?: false, crit_chance: 0}
        refute AttackTable.resolve(unshielded, attack, 100, roll: roll).outcome == :block
      end
    end
  end

  describe "block_value/1" do
    test "multiplies shield, strength and flat bonuses together", %{character: character} do
      character = with_auras(character, [holder(:mod_shield_block_value, 30), holder(:mod_shield_block_value_pct, 30)])
      assert CombatRatings.block_value(character) == 72
    end

    test "retains fractional strength until the final truncation", %{character: character} do
      character = %{character | unit: %{character.unit | strength: 39, equipment_bonuses: %{shield_block: 0}}}
      character = with_auras(character, [holder(:mod_shield_block_value_pct, 30)])
      assert CombatRatings.block_value(character) == 1
    end

    test "scales stacks and multiplies independent percentage bonuses", %{character: character} do
      character =
        with_auras(character, [
          holder(:mod_shield_block_value, 10, 2),
          holder(:mod_shield_block_value_pct, 10, 2),
          holder(:mod_shield_block_value_pct, 50)
        ])

      assert CombatRatings.block_value(character) == 82
    end

    test "clamps negative values and percentages", %{character: character} do
      assert CombatRatings.block_value(with_auras(character, [holder(:mod_shield_block_value, -100)])) == 0
      assert CombatRatings.block_value(with_auras(character, [holder(:mod_shield_block_value_pct, -150)])) == 0
    end

    test "preserves creature block values", %{character: character} do
      character = with_auras(character, [holder(:mod_shield_block_value, 235), holder(:mod_shield_block_value_pct, 30)])
      assert CombatRatings.block_value(%Mob{unit: character.unit}) == 37
    end

    test "uses current equipment and strength", %{character: character} do
      character = with_auras(character, [holder(:mod_shield_block_value_pct, 30)])
      assert CombatRatings.block_value(character) == 33
      character = %{character | unit: %{character.unit | strength: 180, equipment_bonuses: %{shield_block: 40}}}
      assert CombatRatings.block_value(character) == 62
    end
  end

  describe "resolve/4" do
    test "blocks the shared value after armor and caps at incoming damage", %{character: character} do
      character = with_auras(character, [holder(:mod_shield_block_value, 30), holder(:mod_shield_block_value_pct, 30)])
      attack = %{caster_level: 60, caster_player?: false, crit_chance: 0}
      result = AttackTable.resolve(character, attack, 100, roll: 1_200)
      assert result.outcome == :block
      assert result.blocked_amount == 72
      assert result.damage == 28

      armored = %{character | unit: %{character.unit | normal_resistance: 5_000}}
      result = AttackTable.resolve(armored, attack, 100, roll: 1_200)
      assert result.blocked_amount == AttackTable.armor_reduced_damage(100, 5_000, 60)
      assert result.damage == 0
      assert result.victim_state == 5
    end
  end

  describe "from_caster/3" do
    test "snapshots the same block value for Shield Slam", %{character: character} do
      character = with_auras(character, [holder(:mod_shield_block_value, 30), holder(:mod_shield_block_value_pct, 30)])
      spell = %Spell{id: 23_922, school: :physical, dmg_class: 2, effects: []}
      context = CastContext.from_caster(character, spell, 2)
      assert context.shield_block_value == 72
      assert context.shield_block_value == CombatRatings.block_value(character)
    end
  end

  describe "receive_attack/4" do
    test "full and partial blocks spend the last charge and remove the projected bonus", %{character: character} do
      for damage <- [10, 100] do
        {buffed, _} = Aura.apply_spell(character, 1, 60, shield_block(), 0)
        assert [%Holder{charges: 1}] = buffed.unit.auras
        {blocked, events} = Combat.receive_attack(buffed, attack(damage), 1_000, roll: 5_000)

        assert %Effects.AttackOutcome{outcome: :block, damage: remaining} =
                 Enum.find(events, &is_struct(&1, Effects.AttackOutcome))

        assert remaining == max(damage - 26, 0)
        assert blocked.unit.health == 1_000 - remaining
        assert blocked.unit.auras == []
        assert blocked.unit.aura == 0
        assert blocked.unit.aura_applications == <<0::size(48 * 8)>>
        assert blocked.player.block_percentage == 5.0
        assert Aura.next_event_at(blocked) == nil
      end
    end

    test "two charges survive the first block and disappear after the second", %{character: character} do
      spell = %{shield_block() | proc_charges: 2}
      {buffed, _} = Aura.apply_spell(character, 1, 60, spell, 0)
      assert [%Holder{charges: 2, slot: slot}] = buffed.unit.auras
      assert :binary.at(buffed.unit.aura_applications, slot) == 1
      {blocked, _events} = Combat.receive_attack(buffed, attack(10), 1_000, roll: 5_000)
      assert [%Holder{charges: 1, slot: ^slot}] = blocked.unit.auras
      assert :binary.at(blocked.unit.aura_applications, slot) == 0
      assert blocked.player.block_percentage == 80.0
      {blocked, _events} = Combat.receive_attack(blocked, attack(100), 2_000, roll: 5_000)
      assert blocked.unit.auras == []
      assert blocked.player.block_percentage == 5.0
      {_ordinary, events} = Combat.receive_attack(blocked, attack(100), 3_000, roll: 5_000)
      assert %Effects.AttackOutcome{outcome: :normal} = Enum.find(events, &is_struct(&1, Effects.AttackOutcome))
    end

    test "misses, dodges, parries and unblocked hits preserve the charge", %{character: character} do
      {buffed, _} = Aura.apply_spell(character, 1, 60, shield_block(), 0)

      buffed = %{buffed | unit: %{buffed.unit | agility: 100}}

      for {roll, outcome} <- [{0, :miss}, {600, :dodge}, {1_200, :parry}, {9_999, :normal}] do
        {updated, events} = Combat.receive_attack(buffed, attack(100), 1_000, roll: roll)
        assert %Effects.AttackOutcome{outcome: ^outcome} = Enum.find(events, &is_struct(&1, Effects.AttackOutcome))
        assert [%Holder{charges: 1}] = updated.unit.auras
        assert updated.player.block_percentage == 80.0
      end
    end

    test "unused charges are removed on expiry and death", %{character: character} do
      {buffed, _} = Aura.apply_spell(character, 1, 60, shield_block(), 0)
      {expired, _events} = Aura.expire_due(buffed, 5_000)
      assert expired.unit.auras == []
      assert expired.player.block_percentage == 5.0
      dead = Core.take_damage(buffed, 1_000, 1_000)
      assert dead.unit.auras == []
      assert dead.player.block_percentage == 5.0
    end
  end

  describe "apply_spell/5" do
    test "refresh, cancellation, expiry and death restore the derived value", %{character: character} do
      spell = bonus_spell(28_773, :mod_shield_block_value, 235)
      {buffed, _} = Aura.apply_spell(character, 1, 60, spell, 0)
      assert CombatRatings.block_value(buffed) == 261
      {refreshed, _} = Aura.apply_spell(buffed, 1, 60, spell, 5_000)
      assert CombatRatings.block_value(refreshed) == 261
      {expired, _} = Aura.expire_due(refreshed, 25_000)
      assert CombatRatings.block_value(expired) == 26
      assert Aura.next_event_at(expired) == nil
      {cancelled, _} = Aura.cancel_spell(buffed, spell.id, 1_000)
      assert CombatRatings.block_value(cancelled) == 26
      dead = Core.take_damage(buffed, 1_000, 1_000)
      assert dead.unit.health == 0
      assert CombatRatings.block_value(dead) == 26
    end
  end

  describe "resync/3" do
    test "equipped block-value spells contribute once and disappear on unequip", %{character: character} do
      shield = Item.build(%ItemTemplate{entry: 100, inventory_type: 14, block: 20}, 100, owner: 1)

      trinket =
        Item.build(%ItemTemplate{entry: 101, inventory_type: 12, spellid_1: 23_562, spelltrigger_1: 1}, 101, owner: 1)

      use_item = %ItemTemplate{entry: 102, inventory_type: 12, spellid_1: 23_562, spelltrigger_1: 0}
      get_item = fn guid -> %{100 => shield, 101 => trinket}[guid] end
      get_spell = fn 23_562 -> bonus_spell(23_562, :mod_shield_block_value, 30) end
      player = character.player |> Inventory.equip(:offhand, shield) |> Inventory.equip(:trinket1, trinket)
      equipped = EquipmentStats.resync(%{character | player: player}, get_item, get_spell)
      assert CombatRatings.block_value(equipped) == 56
      assert EquipmentStats.resync(equipped, get_item, get_spell) == equipped
      assert EquipmentStats.bonuses([use_item], get_spell).shield_block == 0
      unequipped = EquipmentStats.resync(%{equipped | player: %Player{}}, get_item, get_spell)
      assert CombatRatings.block_value(unequipped) == 6
      assert unequipped.unit.equipment_bonuses.shield_block == 0
    end
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: %Unit{
        health: 1_000,
        max_health: 1_000,
        class: 1,
        level: 60,
        strength: 140,
        agility: 0,
        sheath_state: 1,
        equipment_bonuses: %{shields: 1, shield_block: 20},
        auras: []
      },
      player: %Player{visible_item_16_0: 1},
      internal: %Internal{
        spellbook: %{
          107 => %Spell{id: 107, effects: [%Effect{type: :block}]},
          3127 => %Spell{id: 3127, effects: [%Effect{type: :parry}]}
        }
      }
    }

    %{character: character}
  end

  defp holder(type, amount, stacks \\ 1) do
    %Holder{spell: %Spell{id: 90_000}, auras: [%AuraData{type: type, amount: amount}], stacks: stacks}
  end

  defp with_auras(character, holders), do: %{character | unit: %{character.unit | auras: holders}}

  defp bonus_spell(id, type, amount) do
    %Spell{
      id: id,
      school: :physical,
      duration_ms: 20_000,
      effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: amount, implicit_target_a: :caster}]
    }
  end

  defp shield_block do
    %{
      bonus_spell(2565, :mod_block_percent, 75)
      | duration_ms: 5_000,
        proc_charges: 1,
        proc_type_mask: 0x2A8,
        proc_chance: 100,
        proc_rule: %ProcRule{proc_ex: 0x40}
    }
  end

  defp attack(damage) do
    %{
      caster: 99,
      caster_level: 60,
      caster_player?: false,
      caster_position: {2.0, 0.0, 0.0},
      crit_chance: 0,
      damage: damage
    }
  end
end
