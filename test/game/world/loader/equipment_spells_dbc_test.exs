defmodule ThistleTea.Game.World.Loader.EquipmentSpellsDbcTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.ItemTemplate
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Inventory
  alias ThistleTea.Game.Entity.Logic.Regen
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Spell.Proc
  alias ThistleTea.Game.Spell.ProcRule
  alias ThistleTea.Game.World.CharacterStore
  alias ThistleTea.Game.World.ItemStore
  alias ThistleTea.Game.World.Loader.Item, as: ItemLoader
  alias ThistleTea.Game.World.Loader.Spell, as: SpellLoader
  alias ThistleTea.Game.WorldRef

  @moduletag :dbc_db

  setup [:character]

  describe "sync_equipment_stats/1" do
    test "quiver haste follows weapon changes and restores without a duplicate aura", %{character: character} do
      quiver = %ItemTemplate{
        entry: 18_714,
        class: 11,
        subclass: 2,
        inventory_type: 18,
        container_slots: 18,
        spellid_1: 29_414,
        spelltrigger_1: 1
      }

      bow = %ItemTemplate{
        entry: character.object.guid * 2,
        class: 2,
        subclass: 2,
        inventory_type: 15,
        ammo_type: 2,
        delay: 3_000,
        dmg_min1: 20,
        dmg_max1: 30
      }

      wand = %{bow | entry: bow.entry + 1, subclass: 19, inventory_type: 26, ammo_type: 0, delay: 1_500}

      for template <- [bow, wand] do
        :ets.insert(ItemLoader, {template.entry, template})
        on_exit(fn -> :ets.delete(ItemLoader, template.entry) end)
      end

      assert Enum.any?(SpellLoader.load(29_414).effects, &(&1.aura == :mod_ranged_ammo_haste))
      equipped = character |> equip(:bag1, quiver) |> equip(:ranged, bow) |> Character.sync_equipment_stats()
      assert equipped.unit.equipment_bonuses.ranged_ammo_haste == 15
      assert equipped.unit.ranged_attack_time == 2_608
      assert equipped.unit.auras == []
      assert Character.sync_equipment_stats(equipped).unit == equipped.unit
      swapped = equipped |> equip(:ranged, wand) |> Character.sync_equipment_stats()
      assert swapped.unit.ranged_attack_time == 1_500
      restored = swapped |> equip(:ranged, bow) |> Character.sync_equipment_stats()
      assert restored.unit.ranged_attack_time == 2_608
      removed = Character.sync_equipment_stats(%{restored | player: %{restored.player | bag1: 0}})
      assert removed.unit.ranged_attack_time == 3_000
      assert removed.unit.equipment_bonuses.ranged_ammo_haste == 0
    end

    test "loads item crit and dodge and restores them on reconnect", %{character: character} do
      character =
        character
        |> equip(:chest, %ItemTemplate{entry: 11_726, spellid_1: 7598, spelltrigger_1: 1})
        |> equip(:trinket1, %ItemTemplate{entry: 13_965, spellid_1: 7598, spelltrigger_1: 1})
        |> equip(:neck, %ItemTemplate{entry: 11_755, spellid_1: 13_669, spelltrigger_1: 1})
        |> Character.sync_equipment_stats()

      assert character.player.crit_percentage == 9.0
      assert character.player.dodge_percentage == 6.0
      assert length(character.unit.auras) == 3
      assert Enum.all?(character.unit.auras, &is_nil(&1.slot))
      restored = Character.sync_equipment_stats(%{character | unit: %{character.unit | auras: []}})
      assert restored.player.crit_percentage == 9.0
      assert restored.player.dodge_percentage == 6.0
      assert length(restored.unit.auras) == 3
      removed = Character.sync_equipment_stats(%{restored | player: %Player{}})
      assert removed.player.crit_percentage == 5.0
      assert removed.player.dodge_percentage == 5.0
      assert removed.unit.auras == []
    end

    test "Tooth of Gnarr regenerates mana during the five second rule", %{character: character} do
      character = %{character | unit: %{character.unit | class: 8}}

      equipped =
        character
        |> equip(:neck, %ItemTemplate{entry: 13_141, spellid_1: 21_361, spelltrigger_1: 1})
        |> Character.sync_equipment_stats()

      assert Regen.tick(equipped, 2_000).unit.power1 == 1
      removed = Character.sync_equipment_stats(%{equipped | player: %Player{}})
      assert Regen.tick(removed, 2_000).unit.power1 == 0
    end

    test "Hand of Justice retains its attack power and gains its extra-attack proc", %{character: character} do
      character =
        character
        |> equip(:trinket1, %ItemTemplate{
          entry: 11_815,
          spellid_1: 9331,
          spelltrigger_1: 1,
          spellid_2: 15_600,
          spelltrigger_2: 1
        })
        |> Character.sync_equipment_stats()

      assert character.unit.attack_power == 380
      assert character.unit.ranged_attack_power == 170

      assert [%{spell: %{id: 15_600}, auras: [%{type: :proc_trigger_spell, trigger_spell_id: 15_601}]}] =
               character.unit.auras

      assert Character.sync_equipment_stats(character).unit == character.unit
    end

    test "Briarwood Reed never doubles spell power", %{character: character} do
      character =
        character
        |> equip(:trinket1, %ItemTemplate{entry: 12_930, spellid_1: 13_881, spelltrigger_1: 1})
        |> Character.sync_equipment_stats()

      assert character.unit.equipment_bonuses.spell_fire == 29
      assert character.unit.equipment_bonuses.healing == 29
      assert character.player.mod_damage_done_pos_fire == 29
      assert character.unit.auras == []
    end

    test "Heart of Wyrmthalak can proc from normal swings at its configured rate", %{character: character} do
      equipped =
        character
        |> equip(:trinket1, %ItemTemplate{entry: 22_321, spellid_1: 27_656, spelltrigger_1: 1})
        |> Character.sync_equipment_stats()

      assert [%{spell: spell, auras: [%{type: :proc_trigger_spell, trigger_spell_id: 27_655}]}] = equipped.unit.auras
      spell = %{spell | proc_rule: %ProcRule{school_mask: 1, ppm_rate: 1.0}}
      assert Proc.eligible?(spell, nil, :deal_melee_swing, :normal)
      assert Proc.roll?(spell, 3_000, fn -> 0.04 end)
      refute Proc.roll?(spell, 3_000, fn -> 0.06 end)
    end

    test "owner publication activates feral weapon attack power only in the allowed forms", %{character: character} do
      character = %{character | unit: %{character.unit | class: 11}}

      character =
        character
        |> equip(:mainhand, %ItemTemplate{entry: 20_580, spellid_1: 24_994, spelltrigger_1: 1})
        |> Character.sync_equipment_stats()

      state = PlayerServer.maybe_broadcast_update(%State{guid: character.object.guid, character: character})
      assert state.character.unit.equipment_bonuses.attack_power == 0
      {shifted, _} = Aura.apply_spell(state.character, character.object.guid, 60, SpellLoader.load(768), 100)
      state = PlayerServer.maybe_broadcast_update(%{state | character: shifted})
      assert state.character.unit.equipment_bonuses.attack_power == 154
      {restored, _} = Aura.cancel_spell(state.character, 768, 200)
      state = PlayerServer.maybe_broadcast_update(%{state | character: restored})
      assert state.character.unit.equipment_bonuses.attack_power == 0
    end
  end

  defp equip(character, slot, template) do
    item = ItemStore.create(template, owner: character.object.guid)
    on_exit(fn -> ItemStore.delete(item.object.guid) end)
    %{character | player: Inventory.equip(character.player, slot, item)}
  end

  defp character(_context) do
    guid = System.unique_integer([:positive, :monotonic]) + 2_000_000
    on_exit(fn -> :ets.delete(CharacterStore, guid) end)

    character = %Character{
      id: guid,
      object: %Object{guid: guid},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0), last_mana_use_at: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      unit: %Unit{
        class: 1,
        level: 60,
        base_strength: 100,
        base_agility: 100,
        base_spirit: 100,
        health: 100,
        max_health: 100,
        base_health: 100,
        power1: 0,
        max_power1: 1_000,
        auras: []
      }
    }

    %{character: character}
  end
end
