defmodule ThistleTea.Game.Entity.Logic.AI.BT.GuardianTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Guardian
  alias ThistleTea.Game.Entity.Data.Component.Internal.Pet
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Guardian, as: GuardianBT
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.WorldRef

  setup [:guardian]

  describe "lifetime/3" do
    test "dead owners retain fighting guardians until combat ends", %{guardian: guardian} do
      dead_owner = %{owner() | metadata: %{alive?: false}}
      fighting = %{guardian | internal: %{guardian.internal | in_combat: true}}
      assert {:failure, ^fighting, _} = GuardianBT.lifetime(fighting, %Blackboard{}, context(dead_owner))
      assert {:success, stopped, _} = GuardianBT.lifetime(guardian, %Blackboard{}, context(dead_owner))
      assert [%Effects.DespawnSelf{}] = stopped.internal.events
    end

    test "missing distant and other-world owners remove combatants", %{guardian: guardian} do
      guardian = %{guardian | internal: %{guardian.internal | in_combat: true}}

      for observation <- [nil, %{owner() | distance: 120.1}, %{owner() | position: {WorldRef.open(1), 0.0, 0.0, 0.0}}] do
        assert {:success, removed, _} = GuardianBT.lifetime(guardian, %Blackboard{}, context(observation))
        assert [%Effects.DespawnSelf{}] = removed.internal.events
      end
    end

    test "duration expiry removes live guardians but preserves corpses", %{guardian: guardian} do
      guardian = %{guardian | internal: %{guardian.internal | guardian: %Guardian{expires_at: 1000}}}
      assert {:success, expired, _} = GuardianBT.lifetime(guardian, %Blackboard{}, context(owner()))
      assert [%Effects.DespawnSelf{}] = expired.internal.events
      corpse = %{guardian | unit: %{guardian.unit | health: 0}}
      assert {{:running, _}, ^corpse, _} = GuardianBT.lifetime(corpse, %Blackboard{}, context(owner()))
      dead_owner = %{owner() | metadata: %{alive?: false}}
      assert {{:running, _}, ^corpse, _} = GuardianBT.lifetime(corpse, %Blackboard{}, context(dead_owner))
    end
  end

  defp guardian(_context) do
    %{
      guardian: %Mob{
        object: %Object{guid: 2},
        unit: %Unit{health: 100, max_health: 100, level: 20},
        internal: %Internal{
          world: WorldRef.open(0),
          in_combat: false,
          guardian: %Guardian{},
          pet: %Pet{owner_guid: 1, kind: :guardian, profile: :combat}
        },
        movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
      }
    }
  end

  defp owner,
    do: %Observation{
      guid: 1,
      position: {WorldRef.open(0), 0.0, 0.0, 0.0},
      distance: 0.0,
      metadata: %{alive?: true, orientation: 0.0}
    }

  defp context(observation) do
    entities = if observation, do: %{1 => observation}, else: %{}
    Context.new(1000, perception: Perception.new(1000, {WorldRef.open(0), 0.0, 0.0, 0.0}, entities, %{}))
  end
end
