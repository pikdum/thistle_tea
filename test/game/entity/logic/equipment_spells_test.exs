defmodule ThistleTea.Game.Entity.Logic.EquipmentSpellsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Item
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.AttackTable
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.CombatRatings
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.EquipmentAuras
  alias ThistleTea.Game.Entity.Logic.EquipmentSpells
  alias ThistleTea.Game.Entity.Logic.EquipmentStats
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Entity.Logic.SpellResist
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.ProcRule

  setup [:character]

  describe "spell_ids/1" do
    test "selects equip triggers from all five slots without repeating a spell" do
      template = %ItemTemplate{
        spellid_1: 1,
        spelltrigger_1: 0,
        spellid_2: 2,
        spelltrigger_2: 1,
        spellid_3: 3,
        spelltrigger_3: 2,
        spellid_4: 2,
        spelltrigger_4: 1,
        spellid_5: 5,
        spelltrigger_5: 1
      }

      assert EquipmentSpells.spell_ids(template) == [2, 5]
      assert EquipmentSpells.spell_ids(%ItemTemplate{}) == []
    end
  end

  describe "sources/1" do
    test "includes equipped bags but excludes storage and broken gear", %{character: character} do
      broken = item(11)
      broken = %{broken | item: %{broken.item | durability: 0}}
      player = %{character.player | chest: 10, head: 11, bag1: 12, inv1: 13, bank1: 14}
      get_item = lookup([item(10), broken, item(12), item(13), item(14)])

      assert player |> Inventory.usable_equipped_items(get_item) |> EquipmentSpells.sources() ==
               [{:item_equip, 10, 1}, {:item_equip, 12, 1}]
    end
  end

  describe "sync/5" do
    test "identical item passives stack and remove independently", %{character: character} do
      items = [item(10), item(11)]
      spell = passive(:mod_crit_percent, 2)
      character = %{character | player: %{character.player | chest: 0, finger1: 10, finger2: 11}}
      both = sync(character, items, [spell])
      assert both.player.crit_percentage == 9.0
      assert both.player.ranged_crit_percentage == 9.0
      assert AttackTable.attacker_context(both).crit_chance == 9.0
      assert length(both.unit.auras) == 2
      assert Enum.all?(both.unit.auras, &is_nil(&1.slot))
      assert sync(both, items, [spell]) == both

      one = sync(%{both | player: %{both.player | finger1: 0}}, items, [spell])
      assert one.player.crit_percentage == 7.0
      assert [%Holder{item_source: {:item_equip, 11, 1}}] = one.unit.auras
      removed = sync(%{one | player: %{one.player | finger2: 0}}, items, [spell])
      assert removed.player.crit_percentage == 5.0
      assert removed.unit.auras == []
    end

    test "mixed equip spells apply stats and passive effects exactly once", %{character: character} do
      spell = %Spell{
        id: 1,
        effects: [
          effect(:mod_attack_power, 20),
          effect(:mod_crit_percent, 2),
          effect(:mod_hit_chance, 1)
        ]
      }

      equipped = sync(character, [item(10)], [spell])
      assert equipped.unit.attack_power == 380
      assert equipped.unit.equipment_bonuses.attack_power == 20
      assert equipped.player.crit_percentage == 7.0
      assert AttackTable.attacker_context(equipped).hit_chance_bonus == 1
      assert Aura.flat_amount(equipped, :mod_attack_power) == 0
      assert sync(equipped, [item(10)], [spell]) == equipped

      for dmg_class <- [2, 3] do
        attack = %Spell{dmg_class: dmg_class, effects: [%Effect{type: :weapon_damage}]}
        context = CastContext.from_caster(equipped, attack, 2)
        assert context.melee_crit_chance == 7.0
        assert context.hit_chance_bonus == 1
      end
    end

    test "pure stat spells need no redundant aura holders", %{character: character} do
      equipped = sync(character, [item(10)], [passive(:mod_attack_power, 20)])
      assert equipped.unit.attack_power == 380
      assert equipped.unit.auras == []
    end

    test "skill and parry bonuses coexist with ordinary auras", %{character: character} do
      character = %{
        character
        | player: %{character.player | visible_item_16_0: 1},
          internal: %{character.internal | spellbook: %{3127 => %Spell{id: 3127, effects: [%Effect{type: :parry}]}}}
      }

      skill = %{effect(:mod_skill, 5) | misc_value: 95}
      spell = %Spell{id: 1, effects: [skill, effect(:mod_parry_percent, 2)]}
      ordinary = %Spell{id: 2, effects: [effect(:mod_crit_percent, 3)]}
      {character, _} = Aura.apply_spell(character, 1, 60, ordinary, 0)
      equipped = sync(character, [item(10)], [spell])
      assert equipped.player.skill_bonuses == %{95 => {5, 0}}
      assert equipped.player.parry_percentage == 7.2
      assert equipped.player.dodge_percentage == 5.2
      assert equipped.player.crit_percentage == 8.0
      assert sync(equipped, [item(10)], [spell]) == equipped
      removed = sync(%{equipped | player: %{equipped.player | chest: 0}}, [item(10)], [spell])
      assert removed.player.skill_bonuses == %{}
      assert removed.player.parry_percentage == 5.0
      assert removed.player.crit_percentage == 8.0
      assert [%Holder{spell: %{id: 2}, item_source: nil}] = removed.unit.auras
    end

    test "breakage removes passives and repair restores them", %{character: character} do
      intact = item(10)
      broken = %{intact | item: %{intact.item | durability: 0}}
      spell = passive(:mod_dodge, 2)
      equipped = sync(character, [intact], [spell])
      assert equipped.player.dodge_percentage == 7.0
      damaged = sync(equipped, [broken], [spell])
      assert damaged.player.dodge_percentage == 5.0
      assert damaged.unit.auras == []
      repaired = sync(damaged, [intact], [spell])
      assert repaired.player.dodge_percentage == 7.0
      assert length(repaired.unit.auras) == 1
    end

    test "survives death and restores from equipped items without being cancelable", %{character: character} do
      items = [item(10)]
      spells = [passive(:mod_crit_percent, 2)]
      equipped = sync(character, items, spells)
      {cancelled, _events} = Aura.cancel_spell(equipped, 1, 100)
      assert cancelled.unit.auras == equipped.unit.auras
      dead = Core.take_damage(equipped, 1_000, 2, now: 100)
      assert length(dead.unit.auras) == 1
      {revived, _events} = Death.resurrect(dead, 1.0, 200)
      assert revived.player.crit_percentage == 7.0
      restored = sync(%{revived | unit: %{revived.unit | auras: []}}, items, spells)
      assert restored.player.crit_percentage == 7.0
      assert length(restored.unit.auras) == 1
    end

    test "honors form restrictions for both stats and auras", %{character: character} do
      spell = %Spell{id: 1, stances: 1, effects: [effect(:mod_attack_power, 100), effect(:mod_crit_percent, 2)]}
      items = [item(10)]
      humanoid = sync(character, items, [spell])
      assert humanoid.unit.attack_power == 360
      assert humanoid.player.crit_percentage == 5.0
      form = %Spell{id: 2, effects: [%Effect{type: :apply_aura, aura: :mod_shapeshift, misc_value: 1}]}
      {shifted, _events} = Aura.apply_spell(humanoid, 1, 60, form, 0)
      shifted = sync(shifted, items, [spell])
      assert shifted.unit.attack_power == 460
      assert shifted.player.crit_percentage == 7.0
      {cancelled, _events} = Aura.cancel_spell(shifted, 2, 100)
      restored = sync(cancelled, items, [spell])
      assert restored.unit.attack_power == 360
      assert restored.player.crit_percentage == 5.0
    end

    test "mana regeneration works while casting and stops on unequip", %{character: character} do
      unit = %{character.unit | class: 8, spirit: 100, power1: 0, max_power1: 1_000}
      character = %{character | unit: unit, internal: %{character.internal | last_mana_use_at: 0}}
      spell = passive(:mod_power_regen, 15)
      equipped = sync(character, [item(10)], [spell])
      assert Regen.tick(equipped, 2_000).unit.power1 == 6
      removed = sync(%{equipped | player: %{equipped.player | chest: 0}}, [item(10)], [spell])
      assert Regen.tick(removed, 2_000).unit.power1 == 0
    end

    test "spell hit and crit passives reach their combat consumers", %{character: character} do
      spell = %Spell{id: 1, effects: [effect(:mod_spell_hit_chance, 2), effect(:mod_spell_crit_chance, 3)]}
      equipped = sync(character, [item(10)], [spell])
      context = CastContext.from_caster(equipped, %Spell{school: :fire, dmg_class: 1}, 2)
      hit_bonus = Aura.flat_amount(equipped, :mod_spell_hit_chance)
      assert hit_bonus == 2
      assert SpellResist.magic_hit?(60, 60, false, hit_bonus: hit_bonus, roll: 9_600)
      refute SpellResist.magic_hit?(60, 60, false, roll: 9_600)
      assert context.spell_crit_chance == 3.0
    end

    test "procs preserve cooldowns across unrelated resyncs and stop on removal", %{character: character} do
      spell = %Spell{
        id: 1,
        proc_type_mask: 4,
        proc_chance: 100,
        proc_rule: %ProcRule{school_mask: 1, cooldown_ms: 1_000},
        effects: [%Effect{type: :apply_aura, aura: :proc_trigger_spell, trigger_spell_id: 5}]
      }

      equipped = sync(character, [item(10)], [spell])
      context = %{victim_guid: 2, outcome: :normal, proc_type: :deal_melee_swing, now: 100}
      {procced, events} = Aura.reactions(equipped, :melee_hit_dealt, context)
      assert [%Effects.TriggerSpell{spell_id: 5, target_guid: 2}] = events
      resynced = sync(procced, [item(10)], [spell])
      assert {_, []} = Aura.reactions(resynced, :melee_hit_dealt, %{context | now: 200})
      moved = sync(%{resynced | player: %{resynced.player | chest: 0, head: 10}}, [item(10)], [spell])
      assert moved.unit.auras == resynced.unit.auras
      assert {_, [%Effects.TriggerSpell{}]} = Aura.reactions(resynced, :melee_hit_dealt, %{context | now: 1_100})
      removed = sync(%{resynced | player: %{resynced.player | chest: 0}}, [item(10)], [spell])
      assert {_, []} = Aura.reactions(removed, :melee_hit_dealt, %{context | now: 2_000})
    end

    test "missing spells leave no holder and never prevent removal", %{character: character} do
      equipped = sync(character, [item(10)], [passive(:mod_crit_percent, 2)])
      assert sync(character, [item(10)], []).unit.auras == []
      assert sync(%{equipped | player: %{equipped.player | chest: 0}}, [item(10)], []).unit.auras == []
    end
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      internal: %Internal{},
      movement_block: %MovementBlock{},
      player: %Player{chest: 10},
      unit: %Unit{
        class: 1,
        level: 60,
        health: 100,
        max_health: 100,
        base_health: 100,
        base_strength: 100,
        base_agility: 100,
        auras: []
      }
    }

    %{character: character}
  end

  defp item(guid),
    do: Item.build(%ItemTemplate{entry: 1, spellid_1: 1, spelltrigger_1: 1, max_durability: 50}, guid, owner: 1)

  defp effect(aura, amount), do: %Effect{type: :apply_aura, aura: aura, base_points: amount, misc_value: 0}
  defp passive(aura, amount), do: %Spell{id: 1, effects: [effect(aura, amount)]}

  defp lookup(items) do
    items = Map.new(items, &{&1.object.guid, &1})
    &Map.get(items, &1)
  end

  defp sync(character, items, spells) do
    get_item = lookup(items)
    spells = Map.new(spells, &{&1.id, &1})
    get_spell = &Map.get(spells, &1)
    sources = character.player |> Inventory.usable_equipped_items(get_item) |> EquipmentSpells.sources()

    character
    |> EquipmentStats.resync(get_item, get_spell)
    |> EquipmentAuras.sync([], get_spell, 0, sources)
    |> CombatRatings.sync()
  end
end
