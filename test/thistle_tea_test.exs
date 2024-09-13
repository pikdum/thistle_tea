defmodule ThistleTeaTest do
  use ExUnit.Case
  import ThistleTea.Mob
  import ThistleTea.Util

  require Logger

  test "future_position" do
    assert future_position(0, 0, 0, 1, 1) == {1, 0}
    assert future_position(0, 0, 0, 10, 1) == {10, 0}
    assert future_position(0, 0, 0, 1, 10) == {10, 0}
    {x, _} = future_position(0, 0, :math.pi(), 1, 10)
    assert x == -10
  end

  test "movement duration" do
    assert calculate_movement_duration({0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}, 1.0) == 5.0
    path = [{0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}, {3.0, 4.0, 5.0}]
    assert calculate_total_duration(path, 1.0) === 10.0
  end

  test "pack guid" do
    guid = 0x123
    extra = <<0xAA>>
    packed = pack_guid(guid) <> extra
    {unpacked, rest} = unpack_guid(packed)
    assert unpacked == guid
    assert rest == extra
  end

  test "pack vector" do
    vector = {1, 2, 3}
    packed = pack_vector(vector)
    assert unpack_vector(packed) == vector
  end
end
