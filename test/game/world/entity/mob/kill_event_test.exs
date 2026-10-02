defmodule ThistleTea.Game.World.Entity.Mob.KillEventTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.AIEvent
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Combat.KillFeedback
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Creature
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.Mob, as: MobServer
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Test.Unique

  @gloat "%s squeezes the last bit of life out of $n."

  describe "handle_cast/2 kill_outcome" do
    test "the killing blow fires the kill event before the victim's death is published" do
      player = Guid.from_low_guid(:player, Unique.integer())
      world = WorldRef.open(0)
      {:ok, _} = Entity.register(player)
      SpatialHash.update(:players, player, world, 1.0, 0.0, 0.0)

      on_exit(fn ->
        Entity.unregister(player)
        SpatialHash.remove(:players, player)
      end)

      victim = %KillFeedback.Victim{guid: player, level: 60, reward_target?: true}

      assert {:noreply, mob, {:continue, :maybe_broadcast}} = MobServer.handle_cast({:kill_outcome, victim}, mob(world))
      Process.cancel_timer(mob.internal.ai_tick_ref)

      assert_receive {:"$gen_cast",
                      {:send_packet, %Message.SmsgMessagechat{chat_type: 0x0D, message: @gloat, target_guid: ^player},
                       _opts}}
    end
  end

  defp mob(world) do
    gloat = %ScriptStep{
      command: :talk,
      texts: [%{text: @gloat, chat_type: :text_emote, language: 0, emote_id: 0}]
    }

    %Mob{
      object: %Object{guid: Guid.from_low_guid(:mob, 15_625, Unique.integer()), entry: 15_625},
      unit: %Unit{health: 100, max_health: 100, level: 63, auras: [], combat_reach: 1.5},
      internal: %Internal{
        world: world,
        name: "Twilight Corrupter",
        creature: %Creature{
          ai_events: [%AIEvent{id: 1, event_type: :kill, param3: 1, repeatable?: true, actions: [[gloat]]}]
        }
      },
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }
  end
end
