defmodule ThistleTea.Game.Network.BinaryUtilsTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Network.BinaryUtils

  describe "pack_guid/1" do
    test "packs integer guid" do
      guid = 0x123
      packed = BinaryUtils.pack_guid(guid)
      assert is_binary(packed)
      {unpacked, <<>>} = BinaryUtils.unpack_guid(packed)
      assert unpacked == guid
    end

    test "packs binary guid" do
      guid = <<0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0>>
      packed = BinaryUtils.pack_guid(guid)
      {unpacked, <<>>} = BinaryUtils.unpack_guid(packed)
      assert unpacked == 0x123456789ABCDEF0
    end

    test "handles zero guid" do
      packed = BinaryUtils.pack_guid(0)
      {unpacked, <<>>} = BinaryUtils.unpack_guid(packed)
      assert unpacked == 0
    end

    test "handles guid with some zero bytes" do
      packed = BinaryUtils.pack_guid(0x1234000000000000)
      {unpacked, <<>>} = BinaryUtils.unpack_guid(packed)
      assert unpacked == 0x1234000000000000
    end
  end

  describe "unpack_guid/1" do
    test "returns remaining data" do
      guid = 0x123
      extra = <<0xAA, 0xBB>>
      packed = BinaryUtils.pack_guid(guid) <> extra
      {unpacked, rest} = BinaryUtils.unpack_guid(packed)
      assert unpacked == guid
      assert rest == extra
    end
  end

  describe "pack_vector/1 and unpack_vector/1" do
    test "roundtrips basic vector" do
      vector = {1.0, 2.0, 3.0}
      packed = BinaryUtils.pack_vector(vector)
      assert BinaryUtils.unpack_vector(packed) == vector
    end

    test "roundtrips zero vector" do
      vector = {0.0, 0.0, 0.0}
      packed = BinaryUtils.pack_vector(vector)
      assert BinaryUtils.unpack_vector(packed) == vector
    end

    test "clamps to valid ranges" do
      large_vector = {10_000.0, 20_000.0, 30_000.0}
      packed = BinaryUtils.pack_vector(large_vector)
      unpacked = BinaryUtils.unpack_vector(packed)
      assert is_tuple(unpacked)
      assert tuple_size(unpacked) == 3
    end
  end

  describe "parse_string/1" do
    test "parses null-terminated string" do
      binary = <<?H, ?e, ?l, ?l, ?o, 0, ?W, ?o, ?r, ?l, ?d>>
      assert {:ok, "Hello", "World"} == BinaryUtils.parse_string(binary)
    end

    test "handles empty string" do
      assert {:ok, "", ""} == BinaryUtils.parse_string(<<0>>)
    end
  end

  describe "parse_string/2" do
    test "starts from given position" do
      binary = <<?H, ?e, ?l, ?l, ?o, 0, ?W>>
      assert {:ok, "Hello", "W"} == BinaryUtils.parse_string(binary, 1)
    end
  end
end
