defmodule ThistleTea.Game.Spell.CastTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastResolution
  alias ThistleTea.Game.Spell.CastResolution.Costs
  alias ThistleTea.Game.Spell.CastResolution.Followups
  alias ThistleTea.Game.Spell.Target

  describe "transition/2" do
    test "accepts only state-machine edges" do
      cast = Cast.new(%Spell{id: 1}, Target.none(), 1_000)
      resolution = resolution()

      cast =
        cast
        |> Cast.transition(:launch)
        |> Cast.put_resolution(resolution)
        |> Cast.transition(:impact)
        |> Cast.transition(:channel_tick)
        |> Cast.transition(:finish)

      assert cast.phase == :finish
      assert cast.resolution == resolution
    end

    test "rejects skipped phases" do
      cast = Cast.new(%Spell{id: 1}, Target.none(), 1_000)

      assert_raise ArgumentError, ~r/preparing.*impact/, fn ->
        Cast.transition(cast, :impact)
      end
    end
  end

  defp resolution do
    %CastResolution{
      hits: [],
      misses: [],
      costs: %Costs{
        power: %CastResolution.PowerCost{power_type: 0, amount: 0},
        channel_power: %CastResolution.PowerCost{power_type: 0, amount: 0},
        reagents: [],
        ammo: [],
        cast_item_guid: nil,
        modifier_holder_ids: []
      },
      impacts: [],
      followups: %Followups{
        packet_hits: [],
        selected_unit_guid: nil,
        object_guid: nil,
        item_guid: nil,
        ground_position: nil,
        area_position: nil
      }
    }
  end
end
