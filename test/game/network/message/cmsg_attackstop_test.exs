defmodule ThistleTea.Game.Network.Message.CmsgAttackstopTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.AI.BT.Blackboard
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message.CmsgAttackstop

  describe "handle/2" do
    test "stops auto attack without resetting the swing timer" do
      player_guid = Guid.from_low_guid(:player, unique_id())
      target_guid = Guid.from_low_guid(:mob, 1, unique_id())

      state =
        CmsgAttackstop.handle(%CmsgAttackstop{}, %{
          guid: player_guid,
          character: %Character{
            object: %Object{guid: player_guid},
            unit: %Unit{target: target_guid},
            movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
            internal: %Internal{
              map: 0,
              in_combat: true,
              blackboard: %Blackboard{next_attack_at: 12_345, attack_started: true, auto_attacking: true}
            }
          },
          player_tick_ref: nil
        })

      assert state.character.internal.blackboard.next_attack_at == 12_345
      assert state.character.internal.blackboard.attack_started == false
      assert state.character.internal.blackboard.auto_attacking == false
    end
  end

  defp unique_id do
    System.unique_integer([:positive, :monotonic])
  end
end
