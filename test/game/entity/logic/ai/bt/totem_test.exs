defmodule ThistleTea.Game.Entity.Logic.AI.BT.TotemTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Totem
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception
  alias ThistleTea.Game.Entity.Logic.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Entity.Logic.AI.BT.Totem, as: TotemBT
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.WorldRef

  describe "lifetime/3" do
    test "expires independently of combat and rejects absent, distant, and other-copy owners" do
      ward = ward(1)
      observation = owner(1)
      assert {:failure, ^ward, _} = TotemBT.lifetime(ward, %Blackboard{}, context(observation, 999))

      for {observed, now} <- [
            {observation, 1000},
            {nil, 999},
            {%{observation | distance: 120.1}, 999},
            {%{observation | position: {WorldRef.instance(529, 2), 0.0, 0.0, 0.0}}, 999}
          ] do
        assert {:success, stopped, _} = TotemBT.lifetime(ward, %Blackboard{}, context(observed, now))
        assert [%Effects.DespawnSelf{duration_ms: 0}] = stopped.internal.events
      end
    end

    test "player death removes wards but creature death preserves them until expiry" do
      assert {:success, _stopped, _} =
               TotemBT.lifetime(ward(1), %Blackboard{}, context(%{owner(1) | metadata: %{alive?: false}}, 999))

      guid = Guid.runtime(:mob, 1234)
      ward = ward(guid)

      assert {:failure, ^ward, _} =
               TotemBT.lifetime(ward, %Blackboard{}, context(%{owner(guid) | metadata: %{alive?: false}}, 999))
    end
  end

  defp ward(owner) do
    %Mob{
      object: %Object{guid: 2},
      unit: %Unit{health: 1500, max_health: 1500},
      internal: %Internal{
        world: WorldRef.instance(529, 1),
        totem: %Totem{owner_guid: owner, expires_at: 1000},
        in_combat: true
      }
    }
  end

  defp owner(guid),
    do: %Observation{
      guid: guid,
      position: {WorldRef.instance(529, 1), 0.0, 0.0, 0.0},
      distance: 2.0,
      metadata: %{alive?: true}
    }

  defp context(observation, now) do
    entities = if observation, do: %{observation.guid => observation}, else: %{}
    Context.new(now, perception: Perception.new(now, nil, entities, %{}))
  end
end
