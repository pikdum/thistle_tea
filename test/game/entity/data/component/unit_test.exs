defmodule ThistleTea.Game.Entity.Data.Component.UnitTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Component.Unit

  describe "bytes_0/1" do
    test "packs race, class, gender, power_type into bytes" do
      attrs = %{race: 1, class: 2, gender: 0, power_type: 3}
      result = Unit.bytes_0(attrs)
      assert is_binary(result)
      assert byte_size(result) == 4
    end

    test "handles max values" do
      attrs = %{race: 255, class: 255, gender: 255, power_type: 255}
      result = Unit.bytes_0(attrs)
      assert is_binary(result)
      assert byte_size(result) == 4
    end

    test "handles zero values" do
      attrs = %{race: 0, class: 0, gender: 0, power_type: 0}
      result = Unit.bytes_0(attrs)
      assert result == <<0, 0, 0, 0>>
    end
  end

  describe "bytes_1/1" do
    test "packs stand_state, pet_loyalty, shapeshift_form, vis_flag" do
      attrs = %{
        stand_state: 1,
        pet_loyalty: 2,
        shapeshift_form: 3,
        vis_flag: 0
      }

      result = Unit.bytes_1(attrs)
      assert is_binary(result)
      assert byte_size(result) == 4
    end

    test "handles typical warrior values" do
      attrs = %{
        stand_state: 0,
        pet_loyalty: 0,
        shapeshift_form: 0,
        vis_flag: 0
      }

      result = Unit.bytes_1(attrs)
      assert is_binary(result)
      assert byte_size(result) == 4
    end
  end

  describe "bytes_2/1" do
    test "packs sheath_state, misc_flags, pet_flags" do
      attrs = %{
        sheath_state: 1,
        misc_flags: 2,
        pet_flags: 3
      }

      result = Unit.bytes_2(attrs)
      assert is_binary(result)
      assert byte_size(result) == 4
    end

    test "includes trailing zero byte" do
      attrs = %{
        sheath_state: 0,
        misc_flags: 0,
        pet_flags: 0
      }

      result = Unit.bytes_2(attrs)
      assert result == <<0, 0, 0, 0>>
    end
  end
end
