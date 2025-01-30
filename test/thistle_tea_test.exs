defmodule ThistleTeaTest do
  use ExUnit.Case
  alias ThistleTea.Util

  require Logger

  test "movement duration" do
    assert Util.calculate_movement_duration({0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}, 1.0) == 5.0
    path = [{0.0, 0.0, 0.0}, {3.0, 4.0, 0.0}, {3.0, 4.0, 5.0}]
    assert Util.calculate_total_duration(path, 1.0) === 10.0
  end

  test "pack guid" do
    guid = 0x123
    extra = <<0xAA>>
    packed = Util.pack_guid(guid) <> extra
    {unpacked, rest} = Util.unpack_guid(packed)
    assert unpacked == guid
    assert rest == extra
  end

  test "pack vector" do
    vector = {1.0, 2.0, 3.0}
    packed = Util.pack_vector(vector)
    assert Util.unpack_vector(packed) == vector
  end
end
