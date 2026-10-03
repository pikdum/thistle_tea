defmodule ThistleTea.Game.World.Entity.GameObject.CheerSpeakerTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.GameEvent.FireworksLaunch
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.GameObject.CheerSpeaker

  @cheer_speaker 180_749

  describe "start/1" do
    test "cheers and schedules the first firework" do
      state = CheerSpeaker.start(speaker())

      assert [%Effects.PlayObjectSound{sound_id: sound}] = state.internal.events
      assert sound in FireworksLaunch.cheers()
      assert_receive :launch_firework, 2_500
    end

    test "leaves other objects alone" do
      state = %{speaker() | object: %Object{entry: 180_754}}

      assert CheerSpeaker.start(state).internal.events in [nil, []]
      refute_receive :launch_firework, 2_100
    end
  end

  describe "launch/1" do
    test "sends up a city firework and schedules the next" do
      state = CheerSpeaker.launch(speaker())
      sites = FireworksLaunch.sites(0, state.movement_block.position)

      assert [%Effects.SummonGameObject{entry: entry, position: position, owned?: false}] = state.internal.events
      assert entry in FireworksLaunch.fireworks()
      assert position in sites
      assert_receive :launch_firework, 2_500
    end
  end

  defp speaker do
    %GameObject{
      object: %Object{entry: @cheer_speaker},
      movement_block: %MovementBlock{position: {-8862.0, 654.0, 96.0, 0.0}},
      internal: %Internal{world: WorldRef.open(0)}
    }
  end
end
