defmodule ThistleTea.Game.Entity.Logic.ProcEquipmentTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AttackFeedback
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.ProcEquipment
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.SpellFeedback
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.ProcRule

  setup [:character]

  describe "allowed?/3" do
    test "matches the current hand and ignores the cast inventory-type restriction", %{character: character} do
      sword = %{proc_spell() | equipped_item_inventory_type_mask: 0x20000}
      assert ProcEquipment.allowed?(character, sword, %{})
      refute ProcEquipment.allowed?(character, sword, %{hand: :offhand})
      refute ProcEquipment.allowed?(character, sword, %{spell: %Spell{dmg_class: 3}})

      bow = %{sword | equipped_item_subclass_mask: 4}
      assert ProcEquipment.allowed?(character, bow, %{spell: %Spell{dmg_class: 3}})
      repeat = %Spell{attributes: MapSet.new([:auto_repeat])}
      assert ProcEquipment.allowed?(character, bow, %{spell: repeat})
      refute ProcEquipment.allowed?(character, %{sword | equipped_item_subclass_mask: 0}, %{})
    end

    test "offhand melee spells select the offhand before other spell attributes", %{character: character} do
      spell = %Spell{dmg_class: 2, attributes: MapSet.new([:requires_offhand_weapon, :auto_repeat])}
      refute ProcEquipment.allowed?(character, proc_spell(), %{spell: spell})
      dagger = %{proc_spell() | equipped_item_subclass_mask: 0x8000}
      assert ProcEquipment.allowed?(character, dagger, %{spell: spell})
      refute ProcEquipment.allowed?(character, dagger, %{spell: %{spell | attributes: MapSet.new()}})
    end

    test "rejects empty and broken hands even when feedback supplies an old weapon", %{character: character} do
      context = %{weapon: character.unit.mainhand_weapon}
      empty = %{character | unit: %{character.unit | mainhand_weapon: nil}}
      refute ProcEquipment.allowed?(empty, proc_spell(), context)

      for hand <- [:mainhand, :offhand, :ranged] do
        broken = %{character | player: %{character.player | broken_equipment: [hand]}}
        spell = %{proc_spell() | equipped_item_subclass_mask: 0xFFFFF}
        refute ProcEquipment.allowed?(broken, spell, %{hand: hand})
      end
    end

    test "disarm blocks the main hand and feral forms block every weapon", %{character: character} do
      holder = %Holder{spell: %Spell{id: 676}, auras: [%AuraData{type: :mod_disarm}]}
      character = %{character | unit: %{character.unit | auras: [holder]}}
      spell = %{proc_spell() | equipped_item_subclass_mask: 0xFFFFF}
      refute ProcEquipment.allowed?(character, spell, %{})
      assert ProcEquipment.allowed?(character, spell, %{hand: :offhand})
      assert ProcEquipment.allowed?(character, spell, %{hand: :ranged})

      for form <- [1, 5, 8], hand <- [:mainhand, :offhand, :ranged] do
        feral = %{character | unit: %{character.unit | class: 11, shapeshift_form: form}}
        refute ProcEquipment.allowed?(feral, spell, %{hand: hand})
      end
    end

    test "armor requirements use the current unbroken shield", %{character: character} do
      spell = %{proc_spell() | equipped_item_class: 4, equipped_item_subclass_mask: 64}
      refute ProcEquipment.allowed?(character, spell, %{})
      shielded = %{character | unit: %{character.unit | equipment_bonuses: %{shields: 1}}}
      assert ProcEquipment.allowed?(shielded, spell, %{hand: :mainhand})
      refute ProcEquipment.allowed?(shielded, %{spell | equipped_item_subclass_mask: 32}, %{})
      broken = %{shielded | player: %{shielded.player | broken_equipment: [:offhand]}}
      refute ProcEquipment.allowed?(broken, spell, %{})
    end

    test "the explicit exemption and creature owners bypass player equipment checks", %{character: character} do
      empty = %{character | unit: %{character.unit | mainhand_weapon: nil}}
      spell = %{proc_spell() | attributes: MapSet.new([:no_proc_equip_requirement])}
      assert ProcEquipment.allowed?(empty, spell, %{})
      assert ProcEquipment.allowed?(empty, %Spell{}, %{})
      assert ProcEquipment.allowed?(%Mob{unit: %Unit{}}, proc_spell(), %{})
    end
  end

  describe "reactions/3" do
    test "outgoing spell feedback preserves charges and cooldown when the current weapon is ineligible", %{
      character: character
    } do
      empty = %{character | unit: %{character.unit | mainhand_weapon: nil}}
      spell = %Spell{id: 133, dmg_class: 1, attributes: MapSet.new([:negative])}
      payload = %{victim_guid: 2, outcome: :crit, proc_type: :deal_harmful_spell, damage: 30}
      rejected = SpellFeedback.receive(empty, payload, spell, 1_000)
      assert rejected.unit.auras == empty.unit.auras
      assert rejected.internal.events == []

      procced = SpellFeedback.receive(character, payload, spell, 1_000)
      assert [%Effects.TriggerSpell{spell_id: 9002}] = procced.internal.events
      assert [%Holder{charges: 1, next_proc_at: 6_000}] = procced.unit.auras
    end

    test "spell and swing feedback select their current offhand or ranged weapon", %{character: character} do
      payload = %{victim_guid: 2, outcome: :normal, damage: 30, hand: :offhand}
      assert AttackFeedback.receive(character, payload, nil, 1_000).internal.events == []

      dagger = replace_proc(character, %{proc_spell() | equipped_item_subclass_mask: 0x8000})

      assert [%Effects.TriggerSpell{spell_id: 9002}] =
               AttackFeedback.receive(dagger, payload, nil, 1_000).internal.events

      payload = %{victim_guid: 2, outcome: :crit, proc_type: :deal_ranged_ability, damage: 30}
      bow = replace_proc(character, %{proc_spell() | equipped_item_subclass_mask: 4})
      spell = %Spell{id: 75, dmg_class: 3}
      assert SpellFeedback.receive(character, payload, spell, 1_000).internal.events == []
      assert [%Effects.TriggerSpell{spell_id: 9002}] = SpellFeedback.receive(bow, payload, spell, 1_000).internal.events
    end

    test "cast-end and kill procs share the requirement while incoming procs remain unrestricted", %{
      character: character
    } do
      character = %{character | unit: %{character.unit | mainhand_weapon: nil}}
      spell = proc_spell()

      for {event, context, proc_ex} <- [
            {:spell_cast_completed, %{spell: %Spell{id: 133}, proc_type: :deal_harmful_spell, outcome: :cast_end},
             0x80000},
            {:kill, %{}, 0}
          ] do
        character = replace_proc(character, %{spell | proc_rule: %ProcRule{proc_ex: proc_ex}})
        context = Map.merge(context, %{victim_guid: 2, now: 1_000})
        assert {^character, []} = Aura.reactions(character, event, context)
      end

      context = %{
        attacker_guid: 2,
        spell: %Spell{id: 133},
        proc_type: :take_harmful_spell,
        outcome: :normal,
        now: 1_000
      }

      assert {_, [%Effects.TriggerSpell{spell_id: 9002}]} = Aura.reactions(character, :spell_hit_taken, context)
    end
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{
        health: 1_000,
        max_health: 1_000,
        level: 60,
        auras: [],
        mainhand_weapon: %{class: 2, subclass: 7, inventory_type: 13},
        offhand_weapon: %{class: 2, subclass: 15, inventory_type: 13},
        ranged_weapon: %{class: 2, subclass: 2, inventory_type: 15}
      },
      player: %Player{},
      internal: %Internal{}
    }

    %{character: replace_proc(character, proc_spell())}
  end

  defp proc_spell do
    %Spell{
      id: 9001,
      proc_chance: 100,
      proc_type_mask: 0x30146,
      proc_rule: %ProcRule{cooldown_ms: 5_000},
      equipped_item_class: 2,
      equipped_item_subclass_mask: 0x80
    }
  end

  defp replace_proc(character, spell) do
    holder = %Holder{
      spell: spell,
      charges: 2,
      caster_guid: character.object.guid,
      auras: [%AuraData{type: :proc_trigger_spell, trigger_spell_id: 9002}]
    }

    %{character | unit: %{character.unit | auras: [holder]}}
  end
end
