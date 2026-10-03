defmodule ThistleTea.Game.World.Entity.GameObject.ElementalRiftTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.AI.BT.Context.Perception.Observation
  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.Internal.Rift
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Guid
  alias ThistleTea.Game.Core.Pet.SummonEvent
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.World.Entity.GameObject.ElementalRift
  alias ThistleTea.Game.World.ServerVariables
  alias ThistleTea.Test.Unique

  @fire_stage 30_008

  setup do
    previous = ServerVariables.get(@fire_stage)
    on_exit(fn -> ServerVariables.put(@fire_stage, previous) end)
    :ok
  end

  describe "start/1" do
    test "only an invasion rift keeps invaders" do
      assert %Rift{element: :fire} = ElementalRift.start(rift(179_666)).internal.rift
      assert ElementalRift.start(rift(1_822)).internal.rift == nil
    end
  end

  describe "upkeep/1" do
    test "calls out invaders until its element's stage count stands" do
      :ok = ServerVariables.put(@fire_stage, 2)
      rift = ElementalRift.start(rift(179_666))
      standing = for _invader <- 1..3, do: Guid.from_low_guid(:mob, 14_460, Unique.integer())
      rift = Enum.reduce(standing, rift, &ElementalRift.summon_event(&2, summon_event(:summoned_unit, &1)))

      summons = rift |> ElementalRift.upkeep() |> summons()

      assert [%Effects.SummonCreature{summon: summon}] = summons
      assert %{entry: 14_460, despawn_type: 1, despawn_delay_ms: 3_600_000, wander_distance: 30.0} = summon
      assert {_x, _y, _z, _o} = summon.home
    end
  end

  describe "summon_event/2" do
    test "forgets invaders that die or leave so the next upkeep replaces them" do
      :ok = ServerVariables.put(@fire_stage, 1)
      guid = Guid.from_low_guid(:mob, 14_460, Unique.integer())
      rift = ElementalRift.start(rift(179_666))

      called = ElementalRift.summon_event(rift, summon_event(:summoned_unit, guid))
      assert MapSet.member?(called.internal.rift.invaders, guid)

      for ending <- [:summoned_just_died, :summoned_just_despawn] do
        gone = ElementalRift.summon_event(called, summon_event(ending, guid))
        assert gone.internal.rift.invaders == MapSet.new()
        assert gone |> ElementalRift.upkeep() |> summons() |> length() == 3
      end
    end
  end

  defp rift(entry) do
    %GameObject{
      object: %Object{guid: Guid.from_low_guid(:game_object, entry, Unique.integer()), entry: entry},
      internal: %Internal{world: WorldRef.open(1)},
      movement_block: %MovementBlock{position: {-7_000.0, -1_000.0, -270.0, 0.0}}
    }
  end

  defp summon_event(event, guid) do
    %SummonEvent{event: event, entry: 14_460, world: WorldRef.open(1), observation: %Observation{guid: guid}}
  end

  defp summons(%GameObject{internal: %{events: events}}),
    do: Enum.filter(events, &is_struct(&1, Effects.SummonCreature))
end
