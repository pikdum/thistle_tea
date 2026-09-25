defmodule ThistleTea.Game.Entity.Logic.DamageSharingTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.DamageSharing
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.WorldRef

  describe "split/5" do
    test "shields absorb before flat shares and successive percentage shares" do
      entity =
        character([
          holder(:split_damage_percent, 50, 3),
          holder(:school_absorb, 20),
          holder(:split_damage_percent, 50, 4),
          holder(:split_damage_flat, 20, 2)
        ])

      {entity, damage, absorbed} =
        Core.take_damage_with_mitigation(entity, 100, 1_000,
          source: 9,
          source_level: 60,
          school: :physical,
          damage_sharing_targets: MapSet.new([2, 3, 4])
        )

      assert {entity.unit.health, damage, absorbed} == {985, 100, 85}
      assert Enum.map(transfers(entity), &{&1.target_guid, &1.damage}) == [{2, 20}, {3, 30}, {4, 15}]
      refute Enum.any?(entity.unit.auras, &Enum.any?(&1.auras, fn aura -> aura.type == :school_absorb end))
    end

    test "full absorption never damages the linked caster" do
      entity = character([holder(:school_absorb, 200), holder(:split_damage_percent, 30, 2)])

      {entity, damage, absorbed} =
        Core.take_damage_with_mitigation(entity, 100, 1_000, damage_sharing_targets: MapSet.new([2]))

      assert {entity.unit.health, damage, absorbed} == {1_000, 100, 100}
      assert transfers(entity) == []
    end

    test "unavailable, expired, self-cast, and other-school shares do not reduce damage" do
      expired = %{holder(:split_damage_flat, 45, 2) | expires_at: 1_000}
      fire = holder(:split_damage_flat, 45, 3, 4)
      entity = character([expired, fire, holder(:split_damage_flat, 45, 1), holder(:split_damage_flat, 45, 4)])

      assert {100, []} =
               DamageSharing.split(entity, 100, :physical, 1_000, damage_sharing_targets: MapSet.new([1, 2, 3]))
    end

    test "flat values are already rolled and stack without adding another point" do
      share = %{holder(:split_damage_flat, 45, 2) | stacks: 2}
      entity = character([share])

      assert {10, [%Effects.SharedDamage{damage: 90}]} =
               DamageSharing.split(entity, 100, :physical, 1_000, damage_sharing_targets: MapSet.new([2]))

      assert {0, [%Effects.SharedDamage{damage: 20}]} =
               DamageSharing.split(entity, 20, :physical, 1_000, damage_sharing_targets: MapSet.new([2]))
    end

    test "percentage shares round down and are bounded by the remaining damage" do
      entity = character([holder(:split_damage_percent, 30, 2)])
      opts = [damage_sharing_targets: MapSet.new([2])]
      assert {2, []} = DamageSharing.split(entity, 2, :physical, 1_000, opts)
      assert {3, [%Effects.SharedDamage{damage: 1}]} = DamageSharing.split(entity, 4, :physical, 1_000, opts)
      entity = character([holder(:split_damage_percent, 200, 2)])
      assert {0, [%Effects.SharedDamage{damage: 100}]} = DamageSharing.split(entity, 100, :physical, 1_000, opts)
    end
  end

  describe "receive/4" do
    test "flat transfers consume shields without reapplying received damage modifiers" do
      recipient = character([holder(:school_absorb, 20), holder(:mod_damage_percent_taken, 100)])
      recipient = DamageSharing.receive(recipient, transfer(:split_damage_flat, 45), 1_000)
      assert recipient.unit.health == 975

      assert [
               %Effects.SpellDamage{
                 spell_id: 6940,
                 source_guid: 9,
                 damage: 45,
                 absorbed: 20,
                 school: :physical,
                 crit?: false,
                 proc_type: nil
               }
             ] = feedback(recipient)

      assert transfers(recipient) == []
    end

    test "percentage transfers bypass the pet's shields, resistance, and received modifiers" do
      recipient = character([holder(:school_absorb, 200), holder(:mod_damage_percent_taken, 100)])
      effect = %{transfer(:split_damage_percent, 30) | spell: %Spell{id: 25_228}, school: :fire}
      recipient = %{recipient | unit: %{recipient.unit | fire_resistance: 300}}
      damaged = DamageSharing.receive(recipient, effect, 1_000, roll: 0)
      assert damaged.unit.health == 970
      assert damaged.unit.auras == recipient.unit.auras

      assert [%Effects.SpellDamage{spell_id: 25_228, damage: 30, absorbed: 0, resisted: 0, school: :fire}] =
               feedback(damaged)
    end

    test "mutual flat links cannot send the damage back" do
      recipient = character([holder(:split_damage_flat, 45, 2), holder(:school_absorb, 200)])
      damaged = DamageSharing.receive(recipient, transfer(:split_damage_flat, 45), 1_000)
      assert damaged.unit.health == 955
      assert damaged.unit.auras == recipient.unit.auras
      assert transfers(damaged) == []
    end

    test "flat transfers respect the recipient's immunity while retaining feedback" do
      recipient = character([holder(:school_immunity, 1)])
      damaged = DamageSharing.receive(recipient, transfer(:split_damage_flat, 45), 1_000)
      assert damaged.unit.health == 1_000
      assert [%Effects.SpellDamage{damage: 45, absorbed: 45}] = feedback(damaged)
    end

    test "flat spell transfers use periodic resistance without another hit or critical roll" do
      effect = %{transfer(:split_damage_flat, 100) | school: :fire}
      recipient = character([])
      recipient = %{recipient | unit: %{recipient.unit | fire_resistance: 300}}
      damaged = DamageSharing.receive(recipient, effect, 1_000, roll: 0)
      assert [%Effects.SpellDamage{resisted: resisted, damage: damage, crit?: false}] = feedback(damaged)
      assert resisted > 0
      assert resisted + damage == 100
      assert damaged.unit.health == 1_000 - damage
    end

    test "lethal sharing uses normal death cleanup and credits the original attacker" do
      recipient = character([holder(:split_damage_percent, 30, 2)])
      dead = DamageSharing.receive(recipient, transfer(:split_damage_percent, 1_000), 1_000)
      assert Core.dead?(dead)
      assert dead.internal.killed_by == 9
      assert dead.unit.auras == []
      assert transfers(dead) == []
      refute Enum.any?(dead.internal.events, &is_struct(&1, Effects.DurabilityDamage))
      assert DamageSharing.receive(dead, transfer(:split_damage_percent, 1), 1_001) == dead
    end

    test "taxi flight absorbs transfers without affecting health" do
      recipient = character([])
      recipient = %{recipient | internal: %{recipient.internal | taxi_flight: %{path_id: 1}}}
      damaged = DamageSharing.receive(recipient, transfer(:split_damage_percent, 30), 1_000)
      assert damaged.unit.health == 1_000
      assert [%Effects.SpellDamage{damage: 30, absorbed: 30}] = feedback(damaged)
    end
  end

  defp transfers(entity), do: Enum.filter(entity.internal.events, &is_struct(&1, Effects.SharedDamage))
  defp feedback(entity), do: Enum.filter(entity.internal.events, &is_struct(&1, Effects.SpellDamage))

  defp transfer(kind, damage) do
    %Effects.SharedDamage{
      target_guid: 1,
      source_guid: 9,
      source_level: 60,
      world: WorldRef.open(0),
      spell: %Spell{id: 6940},
      school: :physical,
      damage: damage,
      kind: kind
    }
  end

  defp holder(type, amount, caster \\ 1, mask \\ 127) do
    %Holder{
      spell: %Spell{id: 6940},
      caster_guid: caster,
      slot: caster,
      auras: [%Aura{type: type, amount: amount, misc_value: mask}]
    }
  end

  defp character(auras) do
    %Character{
      object: %Object{guid: 1},
      unit: %Unit{level: 60, health: 1_000, max_health: 1_000, auras: auras},
      player: %Player{},
      internal: %Internal{},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
