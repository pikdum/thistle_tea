defmodule ThistleTea.Game.Network.BinaryUtilsTest do
  use ExUnit.Case

  alias ThistleTea.Game.Network.BinaryUtils

  test "pack guid" do
    guid = 0x123
    extra = <<0xAA>>
    packed = BinaryUtils.pack_guid(guid) <> extra
    {unpacked, rest} = BinaryUtils.unpack_guid(packed)
    assert unpacked == guid
    assert rest == extra
  end

  test "pack vector" do
    vector = {1.0, 2.0, 3.0}
    packed = BinaryUtils.pack_vector(vector)
    assert BinaryUtils.unpack_vector(packed) == vector
  end
end
