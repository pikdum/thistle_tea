defmodule ThistleTea.Game.Core.Item.EquipmentTransitionsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Item
  alias ThistleTea.Game.Core.Entity.ItemTemplate
  alias ThistleTea.Game.Core.Item.EquipmentTransitions
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cooldowns

  setup [:equipment]

  describe "apply/5" do
    test "starts every on-use spell at a changed slot without item overrides", %{character: character} do
      template = %ItemTemplate{
        spellid_1: 10,
        spellid_2: 20,
        spellid_3: 30,
        spellid_4: 40,
        spellid_5: 50,
        spelltrigger_2: 1,
        spelltrigger_3: 2,
        spellcooldown_1: 600_000,
        spellcategory_1: 99,
        spellcategorycooldown_1: 600_000
      }

      item = Item.build(template, 100)
      character = %{character | player: %{character.player | trinket1: 100}}
      spells = %{10 => %Spell{id: 10, category: 4, category_recovery_time_ms: 5_000}, 50 => %Spell{id: 50}}
      character = EquipmentTransitions.apply(character, %Player{}, lookup(item), &spells[&1], -100_000)

      assert Cooldowns.ready_at(character, spells[10]) == -70_000
      assert Cooldowns.ready_at(character, %Spell{id: 11, category: 4}) == -95_000
      refute Cooldowns.on_cooldown?(character, %Spell{id: 11, category: 99}, -99_000)
      assert Cooldowns.on_cooldown?(character, spells[10], -70_001)
      refute Cooldowns.on_cooldown?(character, spells[10], -70_000)

      assert [%Effects.ItemCooldown{spell_id: 10}, %Effects.ItemCooldown{spell_id: 50}] = character.internal.events

      assert [%{spell_id: 10, item_id: 0, spell_ms: 29_000}, %{spell_id: 50, spell_ms: 29_000}] =
               Cooldowns.initial(character, %{}, -99_000)
    end

    test "ignores exempt gear, inventory moves and unchanged equipment", %{character: character, item: item} do
      equipped = %{character | player: %{character.player | trinket1: 100}}
      assert transition(equipped, equipped.player, item) == equipped
      moved = %{character | player: %{character.player | inv2: 100}}
      assert transition(moved, character.player, item) == moved
      exempt = %{item | internal: %{item.internal | template: %{Item.template(item) | flags: 0x80}}}
      assert transition(equipped, character.player, exempt) == equipped
    end

    test "moving between trinket slots starts a cooldown after expiry", %{character: character, item: item} do
      character = %{character | player: %{character.player | trinket2: 100}}
      changed = transition(character, %Player{trinket1: 100}, item)
      assert Cooldowns.ready_at(changed, %Spell{id: 10}) == 31_000
    end

    test "preserves both shorter and longer active cooldowns", %{character: character, item: item} do
      for duration <- [5_000, 120_000] do
        spell = %Spell{id: 10, recovery_time_ms: duration}
        character = Cooldowns.start(character, spell, 0)
        character = %{character | player: %{character.player | trinket1: 100}}
        changed = transition(character, %Player{}, item)
        assert changed.internal.cooldowns == character.internal.cooldowns
      end
    end

    test "activates a deferred item cooldown using its retained overrides", %{character: character, item: item} do
      spell = %Spell{id: 10, recovery_time_ms: 120_000, attributes: MapSet.new([:cooldown_on_event])}
      character = Cooldowns.start(character, spell, 0, 900)
      character = %{character | player: %{character.player | trinket1: 100}}
      changed = transition(character, %Player{}, item)
      assert Cooldowns.pending(changed, 10) == nil
      assert Cooldowns.ready_at(changed, spell) == 121_000
      assert [%Effects.CooldownEvent{spell_id: 10}, %Effects.ItemCooldown{spell_id: 10}] = changed.internal.events
    end

    test "combat weapon swaps use class-specific GCDs and retain their lock through cast cancellation", %{
      character: character
    } do
      for {class, duration, spell_id} <- [{4, 1_000, 6123}, {1, 1_500, 6119}] do
        character = %{
          character
          | unit: %{character.unit | class: class},
            internal: %{character.internal | in_combat: true}
        }

        character = %{character | player: %{character.player | mainhand: 100}}
        item = Item.build(%ItemTemplate{class: 2, inventory_type: 13}, 100)
        changed = transition(character, %Player{}, item)
        gcd_spell = %Spell{gcd_category: 133}

        assert [%Effects.SpellCooldown{spell_id: ^spell_id, duration_ms: 0}] = changed.internal.events
        assert Cooldowns.on_gcd?(changed, gcd_spell, 1_000 + duration - 1)
        refute Cooldowns.on_gcd?(changed, gcd_spell, 1_000 + duration)
        assert Cooldowns.weapon_change_locked?(changed, 1_000 + duration - 1)
        refute Cooldowns.weapon_change_locked?(changed, 1_000 + duration)
        assert Cooldowns.on_gcd?(Cooldowns.reset_gcd(changed, gcd_spell), gcd_spell, 1_001)
      end
    end

    test "relics start the combat timer but shields and peaceful swaps do not", %{character: character} do
      for {combat?, template, expected} <- [
            {true, %ItemTemplate{inventory_type: 28}, true},
            {true, %ItemTemplate{inventory_type: 14}, false},
            {true, %ItemTemplate{inventory_type: 23}, false},
            {false, %ItemTemplate{class: 2}, false}
          ] do
        equipped = %{
          character
          | player: %{character.player | ranged: 100},
            internal: %{character.internal | in_combat: combat?}
        }

        changed = transition(equipped, %Player{}, Item.build(template, 100))
        assert Cooldowns.weapon_change_locked?(changed, 1_001) == expected
      end
    end

    test "a swap preserves an existing GCD and does not extend a running weapon timer", %{character: character} do
      spell = %Spell{id: 6119, gcd_category: 133, gcd_ms: 1_500}
      character = character |> Cooldowns.trigger_gcd(spell, 0) |> Cooldowns.start_weapon_change(spell, 1_000)
      refute Cooldowns.on_gcd?(character, spell, 1_500)
      assert Cooldowns.weapon_change_locked?(character, 1_500)
      assert Cooldowns.start_weapon_change(character, spell, 1_500) == character
      refute Cooldowns.weapon_change_locked?(character, 2_500)
    end
  end

  describe "validate/4" do
    test "rejects inserting and removing trinkets in combat but permits bag moves", %{character: character, item: item} do
      character = %{character | internal: %{character.internal | in_combat: true}}
      equipped = %{character.player | trinket1: 100}
      assert {:error, :not_in_combat, 100, _} = EquipmentTransitions.validate(character, equipped, lookup(item), 1_000)

      assert {:error, :not_in_combat, _, 100} =
               EquipmentTransitions.validate(%{character | player: equipped}, %Player{}, lookup(item), 1_000)

      assert :ok = EquipmentTransitions.validate(character, %{character.player | inv2: 100}, lookup(item), 1_000)
    end

    test "rejects another weapon until the timer expires and permits a shield", %{character: character} do
      character = %{character | internal: %{character.internal | in_combat: true}}
      spell = %Spell{id: 6119, gcd_category: 133, gcd_ms: 1_500}
      character = Cooldowns.start_weapon_change(character, spell, 1_000)
      player = %{character.player | mainhand: 100}
      weapon = Item.build(%ItemTemplate{class: 2, inventory_type: 13}, 100)
      shield = Item.build(%ItemTemplate{class: 4, inventory_type: 14}, 100)

      assert {:error, :cant_do_right_now, 100, _} =
               EquipmentTransitions.validate(character, player, lookup(weapon), 2_499)

      assert :ok = EquipmentTransitions.validate(character, player, lookup(weapon), 2_500)
      assert :ok = EquipmentTransitions.validate(character, player, lookup(shield), 1_001)
    end
  end

  defp equipment(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, class: 1},
      player: %Player{},
      internal: %Internal{}
    }

    item = Item.build(%ItemTemplate{class: 4, inventory_type: 12, spellid_1: 10}, 100)
    %{character: character, item: item}
  end

  defp lookup(item), do: fn guid -> if guid == item.object.guid, do: item end

  defp transition(character, previous, item) do
    EquipmentTransitions.apply(character, previous, lookup(item), &spell/1, 1_000)
  end

  defp spell(6119), do: %Spell{id: 6119, gcd_category: 133, gcd_ms: 1_500}
  defp spell(6123), do: %Spell{id: 6123, gcd_category: 133, gcd_ms: 1_000}
  defp spell(id), do: %Spell{id: id}
end
