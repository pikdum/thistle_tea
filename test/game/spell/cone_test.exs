defmodule ThistleTea.Game.Spell.ConeTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Spell.Cone

  describe "contains?/3" do
    test "offsets follow the caster's facing without changing the arc" do
      cone = %Cone{degrees: 120, offset_radians: :math.pi() / 2}
      caster = {0.0, 0.0, 0.0, :math.pi() / 2}
      assert Cone.contains?(cone, caster, {-10.0, 0.0, 0.0})
      assert Cone.contains?(cone, caster, {-10.0, 15.0, 0.0})
      refute Cone.contains?(cone, caster, {0.0, 10.0, 0.0})
      refute Cone.contains?(cone, caster, {10.0, 0.0, 0.0})
    end

    test "respects narrow and wide forward arcs" do
      caster = {0.0, 0.0, 0.0, 0.0}
      assert Cone.contains?(7, caster, {10.0, 0.5, 0.0})
      refute Cone.contains?(7, caster, {10.0, 0.7, 0.0})
      assert Cone.contains?(90, caster, {10.0, 9.0, 0.0})
      refute Cone.contains?(60, caster, {10.0, 9.0, 0.0})
      refute Cone.contains?(0, caster, {10.0, 0.0, 0.0})
    end

    test "negative angles select the rear arc" do
      caster = {0.0, 0.0, 0.0, 0.0}
      assert Cone.contains?(-120, caster, {-10.0, 0.0, 0.0})
      assert Cone.contains?(-120, caster, {-10.0, 15.0, 0.0})
      refute Cone.contains?(-120, caster, {-10.0, 20.0, 0.0})
      refute Cone.contains?(-120, caster, {10.0, 0.0, 0.0})
    end

    test "wraps orientation across a full turn" do
      assert Cone.contains?(7, {0.0, 0.0, 0.0, 2 * :math.pi() - 0.02}, {10.0, 0.2, 0.0})
      assert Cone.contains?(60, {0.0, 0.0, 0.0, :math.pi()}, {-10.0, 0.0, 0.0})
      refute Cone.contains?(60, {0.0, 0.0, 0.0, :math.pi()}, {10.0, 0.0, 0.0})
    end
  end
end
