defmodule ThistleTea.Game.Entity.Logic.AI.BT.Pet.AutocastTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Pet.Autocast
  alias ThistleTea.Game.Entity.Logic.Aura, as: AuraLogic
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.WorldRef

  setup [:pet]

  describe "allowed?/4" do
    test "requires enabled autocast and leaves ordinary creatures alone", %{pet: pet} do
      spell = buff()
      assert allowed?(pet, spell)
      refute allowed?(pet, %{spell | id: 2})

      for attribute <- [:passive, :no_autocast_ai] do
        refute allowed?(pet, %{spell | attributes: MapSet.new([attribute])})
      end

      mob = %{pet | internal: %{pet.internal | pet: nil}}
      assert allowed?(mob, %{spell | id: 2})
    end

    test "reserves long-cooldown buffs for an attack target", %{pet: pet} do
      dash = %{buff(:mod_increase_speed) | duration_ms: 15_000, recovery_time_ms: 30_000}
      refute allowed?(pet, dash)
      pet = %{pet | unit: %{pet.unit | target: 2}}
      assert allowed?(pet, dash, 1, context(20.0))
      refute allowed?(pet, dash, 1, context(2.0))
    end

    test "out-of-combat-only buffs and permanent buffs remain available while idle", %{pet: pet} do
      spell = %{buff() | duration_ms: 15_000, recovery_time_ms: 30_000}
      assert allowed?(pet, %{spell | attributes: MapSet.new([:not_in_combat])})
      assert allowed?(pet, %{spell | duration_ms: -1})
    end

    test "attack-cancelling spells cannot undo an attack command before combat contact", %{pet: pet} do
      prowl = %{buff() | attributes: MapSet.new([:cancels_auto_attack_combat, :not_in_combat])}
      assert allowed?(pet, prowl)
      refute allowed?(%{pet | unit: %{pet.unit | target: 2}}, prowl)
    end

    test "a cooldown buff and Tainted Blood require a victim while Fire Shield requires an attacker", %{pet: pet} do
      refute allowed?(pet, buff(:mod_damage_done))
      refute allowed?(pet, %{buff() | spell_icon: 153})
      shield = %{buff() | spell_family: 5, family_flags_0: 0x00800000, spell_visual: 289}
      refute allowed?(pet, shield, 2)
      assert allowed?(pet, shield, 2, context(20.0, %{attacker_count: 1}))
      refute allowed?(pet, shield, 2, context(20.0, %{in_combat: true, attacker_count: 0}))
    end

    test "does not refresh a held effect and allows a partially removed effect", %{pet: pet} do
      spell = buff()
      holder = %Holder{spell: spell, auras: [%Aura{index: 0, type: :mod_stat}]}
      pet = %{pet | unit: %{pet.unit | auras: [holder]}}
      refute allowed?(pet, spell)
      assert allowed?(pet, %{spell | effects: [%Effect{index: 1, type: :apply_aura, aura: :mod_stat}]})
      assert AuraLogic.effect_keys(pet) == MapSet.new([{1, 0}])
      refute allowed?(pet, spell, 2, context(20.0, %{aura_effects: AuraLogic.effect_keys(pet)}))
    end

    test "stacking buffs remain usable and area buffs avoid duplicate effects", %{pet: pet} do
      target = context(20.0, %{aura_effects: MapSet.new([{1, 0}])})
      spell = %{buff() | stack_amount: 3}
      assert allowed?(pet, spell, 2, target)
      spell = %{spell | effects: [%Effect{index: 0, type: :apply_area_aura, aura: :mod_stat}]}
      refute allowed?(pet, spell, 2, target)
    end

    test "stuns skip stunned targets unless the spell also deals direct damage", %{pet: pet} do
      spell = buff(:mod_stun)
      target = context(20.0, %{unit_flags: 0x00040000})
      refute allowed?(pet, spell, 2, target)
      assert allowed?(pet, spell, 2)
      assert allowed?(pet, %{spell | effects: [%Effect{type: :school_damage} | spell.effects]}, 2, target)
    end

    test "heals wait for missing health on self or observed targets", %{pet: pet} do
      spell = buff(:periodic_heal)
      refute allowed?(pet, spell)
      assert allowed?(%{pet | unit: %{pet.unit | health: 99}}, spell)
      refute allowed?(pet, spell, 2, context(20.0, %{health_pct: 100.0}))
      assert allowed?(pet, spell, 2, context(20.0, %{health_pct: 99.0}))
    end
  end

  defp allowed?(pet, spell, target \\ 1, context \\ context()), do: Autocast.allowed?(pet, spell, target, context)

  defp buff(aura \\ :mod_stat) do
    %Spell{id: 1, effects: [%Effect{index: 0, type: :apply_aura, aura: aura, implicit_target_a: :self}]}
  end

  defp context(distance \\ 20.0, metadata \\ %{}) do
    world = WorldRef.open(0)
    observation = %Observation{guid: 2, position: {world, distance, 0.0, 0.0}, distance: distance, metadata: metadata}
    perception = Perception.new(1_000, {world, 0.0, 0.0, 0.0}, %{2 => observation}, %{})
    Context.new(1_000, perception: perception)
  end

  defp pet(_context) do
    pet = %Mob{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, target: 0, auras: [], combat_reach: 1.5},
      internal: %Internal{pet: %Internal.Pet{kind: :hunter, autocast: MapSet.new([1])}},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    %{pet: pet}
  end
end
