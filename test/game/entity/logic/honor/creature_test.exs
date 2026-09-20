defmodule ThistleTea.Game.Entity.Logic.Honor.CreatureTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Creature
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Honor.Award
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EffectResolver.Honor, as: HonorResolver
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Engagement.Tap
  alias ThistleTea.Game.Entity.Logic.Honor
  alias ThistleTea.Game.Party.Group
  alias ThistleTea.Game.Party.Member
  alias ThistleTea.Game.Spell

  setup [:creature]

  describe "creature_award/2" do
    test "penalizes gray civilians and civilians with no XP reward", %{creature: creature} do
      assert %Award{type: :dishonorable, points: 100, victim_rank: 0} = Honor.creature_award(creature, 60)
      assert Honor.creature_award(creature, 10) == nil

      creature = %{
        creature
        | internal: %{creature.internal | creature: %{creature.internal.creature | experience_multiplier: 0}}
      }

      assert %Award{type: :dishonorable, points: 10.0} = Honor.creature_award(creature, 10)
    end

    test "awards a racial leader's fixed honor even when gray", %{creature: creature} do
      creature = %{creature | internal: %{creature.internal | creature: %Creature{racial_leader?: true}}}

      assert %Award{type: :honorable, points: 488, victim_rank: 19, victim_key: {:creature, 2}} =
               Honor.creature_award(creature, 60)
    end
  end

  describe "damage reception" do
    test "requests creature honor only for the first lethal hit", %{creature: creature} do
      creature = Core.take_damage(creature, 100, 1000, source: 7)
      assert [%Effects.HonorCreatureKill{source_guid: 7}] = honor_effects(creature)
      {creature, _effects} = Effects.drain(creature)
      assert [] == creature |> Core.take_damage(100, 1001, source: 7) |> honor_effects()
    end

    test "honorless targets and pets cannot produce a creature award", %{creature: creature} do
      aura = %Holder{spell: %Spell{id: 2479}, auras: [%Aura{type: :honorless_target}]}
      protected = %{creature | unit: %{creature.unit | auras: [aura]}}
      protected = Core.take_damage(protected, 100, 1000, source: 7)
      assert protected.unit.auras == []
      assert honor_effects(protected) == []
      pet = %{creature | internal: %{creature.internal | pet: %Pet{}}}
      assert [] == pet |> Core.take_damage(100, 1000, source: 7) |> honor_effects()
    end
  end

  describe "creature_kill/3" do
    test "awards each nearby living tagged-group member in full", %{creature: creature} do
      group = %Group{id: 10, members: Enum.map(1..4, &%Member{guid: &1})}
      creature = %{creature | internal: %{creature.internal | creature: %Creature{racial_leader?: true}}}
      effect = %Effects.HonorCreatureKill{source_guid: 7}

      opts = [
        group: fn 10 -> group end,
        group_of: fn _guid -> nil end,
        nearby: fn ^creature, 74.0 -> [{1, 0}, {2, 74}, {3, 1}, {7, 1}] end,
        metadata: fn guid -> %{level: 60, alive?: guid != 3} end
      ]

      assert [
               %Effects.HonorAward{target_guid: 1, award: %Award{points: 488}},
               %Effects.HonorAward{target_guid: 2, award: %Award{points: 488}}
             ] = HonorResolver.creature_kill(creature, effect, opts)
    end

    test "checks each member's civilian gray level separately", %{creature: creature} do
      group = %Group{id: 10, members: [%Member{guid: 1}, %Member{guid: 2}]}

      opts = [
        group: fn 10 -> group end,
        group_of: fn _guid -> nil end,
        nearby: fn ^creature, 74.0 -> [{1, 0}, {2, 1}] end,
        metadata: fn guid -> %{level: if(guid == 1, do: 60, else: 10), alive?: true} end
      ]

      assert [%Effects.HonorAward{target_guid: 1, award: %Award{type: :dishonorable, points: 100}}] =
               HonorResolver.creature_kill(creature, %Effects.HonorCreatureKill{source_guid: 7}, opts)
    end
  end

  defp honor_effects(creature), do: Enum.filter(creature.internal.events, &match?(%Effects.HonorCreatureKill{}, &1))

  defp creature(_context) do
    %{
      creature: %Mob{
        object: %Object{guid: 99, entry: 2},
        unit: %Unit{level: 10, health: 100, max_health: 100, auras: []},
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
        internal: %Internal{
          creature: %Creature{civilian?: true, experience_multiplier: 1.0},
          loot: %Loot{tapped_by: %Tap{player: 1, group_id: 10}}
        }
      }
    }
  end
end
