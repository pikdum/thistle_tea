defmodule ThistleTea.Game.World.Entity.PlayerBreathingMapsTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BehaviorRunner
  alias ThistleTea.Game.Core.AI.BT.Player, as: PlayerBT
  alias ThistleTea.Game.Core.Aura
  alias ThistleTea.Game.Core.Aura.Holder
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.World.Entity.AIEnvironment

  @moduletag :namigator_maps

  describe "context/2" do
    test "samples liquid for a stationary protected player before aura expiration" do
      character = %Character{
        object: %Object{guid: 98_020},
        player: %Player{},
        unit: %Unit{
          health: 1000,
          max_health: 1000,
          level: 1,
          auras: [
            %Holder{spell: %Spell{id: 7178}, expires_at: 1000, auras: [%Aura{type: :water_breathing}]}
          ]
        },
        internal: %Internal{},
        movement_block: %MovementBlock{movement_flags: 0, position: {-9500.0, -220.0, 55.47, 0.0}}
      }

      context = AIEnvironment.context(character, 1000)
      assert_in_delta context.liquid_surface, 57.674, 0.01
      {:running, exposed} = BehaviorRunner.tick(PlayerBT.tree(), character, context)
      assert exposed.unit.auras == []
      assert exposed.internal.breath.remaining == 60_000
    end
  end
end
