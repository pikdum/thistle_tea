defmodule ThistleTea.Game.World.Entity.GameObject.GhostMagnetTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.AI.ScriptStep
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.GhostMagnet, as: Magnet
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.Time
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.GameObject.GhostMagnet
  alias ThistleTea.Test.Unique

  @magnet 177_746
  @aura 177_749
  @spectre 11_560
  @position {-12_000.0, -12_000.0, 60.0, 1.5}

  describe "start/1" do
    test "a magnet raises its aura and readies eight spectres for two minutes" do
      started = GhostMagnet.start(magnet(@magnet))

      assert %Magnet{remaining: 8, until: until} = started.internal.magnet
      assert until > Time.now()

      assert [%Effects.SummonGameObject{entry: @aura, duration_ms: 120_000, owned?: false, position: @position}] =
               started.internal.events
    end

    test "other objects are left alone" do
      assert GhostMagnet.start(magnet(177_748)).internal.magnet == nil
    end
  end

  describe "call/1" do
    test "calls a spectre that makes the magnet its home and walks to it" do
      called = @magnet |> magnet() |> GhostMagnet.start() |> clear_events() |> GhostMagnet.call()

      assert called.internal.magnet.remaining == 7

      assert [%Effects.SummonCreature{summon: summon, steps: [home, walk]}] = called.internal.events
      assert %{entry: @spectre, despawn_type: 1, despawn_delay_ms: 120_000} = summon
      assert %ScriptStep{command: :set_home_position, position: {hx, hy, _hz, _ho}} = home
      assert %ScriptStep{command: :move_to, datalong3: 1, datalong4: 2, dataint: 2, position: {^hx, ^hy, _, _}} = walk
      assert_in_delta :math.sqrt((hx - -12_000.0) ** 2 + (hy - -12_000.0) ** 2), 1.5, 0.01
    end

    test "stops once its eight spectres are out or its two minutes are up" do
      spent = put_magnet(magnet(@magnet), %Magnet{until: Time.now() + 60_000, remaining: 0})
      expired = put_magnet(magnet(@magnet), %Magnet{until: Time.now() - 1, remaining: 8})

      assert GhostMagnet.call(spent).internal.events == []
      assert GhostMagnet.call(expired).internal.events == []
    end
  end

  describe "replace/1" do
    test "a slain spectre is replaced only while the magnet still calls" do
      calling = put_magnet(magnet(@magnet), %Magnet{until: Time.now() + 60_000, remaining: 0})
      expired = put_magnet(magnet(@magnet), %Magnet{until: Time.now() - 1, remaining: 0})

      assert GhostMagnet.summon_event(calling, death()) == calling
      assert [%Effects.SummonCreature{summon: %{entry: @spectre}}] = GhostMagnet.replace(calling).internal.events
      assert GhostMagnet.replace(expired).internal.events == []
    end
  end

  defp magnet(entry) do
    %GameObject{
      object: %Object{guid: Guid.from_low_guid(:game_object, entry, Unique.integer()), entry: entry},
      internal: %Internal{world: WorldRef.open(1)},
      movement_block: %MovementBlock{position: @position}
    }
  end

  defp put_magnet(%GameObject{} = magnet, %Magnet{} = state),
    do: %{magnet | internal: %{magnet.internal | magnet: state}}

  defp clear_events(%GameObject{} = magnet), do: %{magnet | internal: %{magnet.internal | events: []}}

  defp death do
    guid = Guid.from_low_guid(:mob, @spectre, Unique.integer())

    %SummonEvent{
      event: :summoned_just_died,
      entry: @spectre,
      world: WorldRef.open(1),
      observation: %Observation{guid: guid}
    }
  end
end
