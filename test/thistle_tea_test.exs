defmodule ThistleTeaTest do
  use ExUnit.Case
  import ThistleTea.Mob
  import ThistleTea.Util

  test "future_position" do
    assert future_position(0, 0, 0, 1, 1) == {1, 0}
    assert future_position(0, 0, 0, 10, 1) == {10, 0}
    assert future_position(0, 0, 0, 1, 10) == {10, 0}
    {x, _} = future_position(0, 0, :math.pi(), 1, 10)
    assert x == -10
  end

  test "pack guid" do
    guid = 0x123
    extra = <<0xAA>>
    packed = pack_guid(guid) <> extra
    {unpacked, rest} = unpack_guid(packed)
    assert unpacked == guid
    assert rest == extra
  end
end
