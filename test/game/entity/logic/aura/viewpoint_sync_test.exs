defmodule ThistleTea.Game.Entity.Logic.Aura.ViewpointSyncTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Logic.Aura.ViewpointSync
  alias ThistleTea.Game.Spell

  describe "events/3" do
    test "grants and releases the viewpoint represented by bind sight" do
      holder = holder(10)

      assert [%{type: :viewpoint_granted, source_guid: 10, target_guid: 20}] =
               ViewpointSync.events([], [holder], 20)

      assert [%{type: :viewpoint_released, source_guid: 10, target_guid: 20}] =
               ViewpointSync.events([holder], [], 20)
    end

    test "transfers a viewpoint between casters and ignores refreshes" do
      previous = holder(10)
      current = holder(11)

      assert ViewpointSync.events([previous], [previous], 20) == []

      assert [
               %{type: :viewpoint_released, source_guid: 10},
               %{type: :viewpoint_granted, source_guid: 11}
             ] = ViewpointSync.events([previous], [current], 20)
    end
  end

  defp holder(caster_guid) do
    %Holder{
      spell: %Spell{id: 2096},
      caster_guid: caster_guid,
      auras: [%Aura{type: :bind_sight}]
    }
  end
end
