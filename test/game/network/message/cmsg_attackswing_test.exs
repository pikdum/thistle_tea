defmodule ThistleTea.Game.Network.Message.CmsgAttackswingTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.CmsgAttackswing
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash

  describe "handle/2" do
    test "sets attack intent but does not enter combat until a swing lands" do
      player_guid = Guid.from_low_guid(:player, unique_guid())
      target_guid = Guid.from_low_guid(:mob, 1, unique_guid())

      Metadata.put(player_guid, %{faction_template: alliance(), attacker_count: 0})

      Metadata.put(target_guid, %{
        faction_template: wolf(),
        faction_can_have_reputation?: false,
        alive?: true,
        unit_flags: 0
      })

      SpatialHash.update(:mobs, target_guid, 0, 1.0, 0.0, 0.0)

      on_exit(fn ->
        Metadata.delete(player_guid)
        Metadata.delete(target_guid)
        SpatialHash.remove(:mobs, target_guid)
      end)

      state =
        CmsgAttackswing.handle(%CmsgAttackswing{target_guid: target_guid}, %{
          guid: player_guid,
          character: character(player_guid),
          player_tick_ref: nil
        })

      refute state.character.internal.in_combat
      assert state.character.unit.target == target_guid
      assert state.character.internal.blackboard.auto_attacking == true
    end
  end

  defp character(guid) do
    %Character{
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100},
      internal: %Internal{map: 0},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end

  defp alliance do
    %FactionTemplate{id: 1, faction: 1, flags: 72, faction_group: 3, friend_group: 2, enemy_group: 12}
  end

  defp wolf do
    %FactionTemplate{id: 32, faction: 29, flags: 16, faction_group: 0, friend_group: 0, enemy_group: 0, enemies_0: 28}
  end

  defp unique_guid do
    System.unique_integer([:positive, :monotonic])
  end
end
