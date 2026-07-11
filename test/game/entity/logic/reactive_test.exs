defmodule ThistleTea.Game.Entity.Logic.ReactiveTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Reactive

  @defense_bit 0x1
  @healthless_bit 0x2

  defp warrior(opts \\ []) do
    %Character{
      object: %Object{guid: 5},
      unit: %Unit{
        class: Keyword.get(opts, :class, 1),
        level: 10,
        health: Keyword.get(opts, :health, 100),
        max_health: 100,
        aura_state: 0,
        auras: []
      },
      player: %Player{},
      internal: %Internal{}
    }
  end

  describe "mark_defense/2" do
    test "sets the defense aura-state bit for four seconds" do
      entity = Reactive.mark_defense(warrior(), 1_000)

      assert Bitwise.band(entity.unit.aura_state, @defense_bit) == @defense_bit
      assert Reactive.defense_active?(entity, 4_999)
      refute Reactive.defense_active?(entity, 5_000)
    end

    test "tick clears the bit after the window" do
      entity = warrior() |> Reactive.mark_defense(1_000) |> Reactive.tick(5_000)

      assert Bitwise.band(entity.unit.aura_state, @defense_bit) == 0
    end

    test "ignores non-players" do
      mob = %Mob{unit: %Unit{health: 100, max_health: 100}, internal: %Internal{}}

      assert Reactive.mark_defense(mob, 1_000) == mob
    end
  end

  describe "sync_health/1" do
    test "sets the healthless bit below twenty percent" do
      entity = Reactive.sync_health(warrior(health: 19))

      assert Bitwise.band(entity.unit.aura_state, @healthless_bit) == @healthless_bit
      assert entity.internal.broadcast_update? == true
    end

    test "clears the healthless bit above twenty percent" do
      entity = %{warrior(health: 50) | unit: %{warrior().unit | health: 50, aura_state: @healthless_bit}}

      assert Bitwise.band(Reactive.sync_health(entity).unit.aura_state, @healthless_bit) == 0
    end

    test "dead units carry no healthless bit" do
      assert Reactive.sync_health(warrior(health: 0)).unit.aura_state == 0
    end

    test "works for mobs so Execute lights on low targets" do
      mob = %Mob{unit: %Unit{health: 15, max_health: 100, aura_state: 0}, internal: %Internal{}}

      assert Bitwise.band(Reactive.sync_health(mob).unit.aura_state, @healthless_bit) == @healthless_bit
    end

    test "preserves the defense bit" do
      entity = warrior() |> Reactive.mark_defense(1_000)
      entity = %{entity | unit: %{entity.unit | health: 10}}

      assert Reactive.sync_health(entity).unit.aura_state == @defense_bit + @healthless_bit
    end
  end

  describe "combo points" do
    test "marking a dodging target grants a combo point on it" do
      entity = Reactive.mark_dodging_target(warrior(), 77, 1_000)

      assert entity.player.field_combo_target == 77
      assert entity.player.combo_points == 1
      assert Reactive.combo_active?(entity, 77, 2_000)
      refute Reactive.combo_active?(entity, 78, 2_000)
      refute Reactive.combo_active?(entity, 77, 5_000)
    end

    test "only warriors get dodge combo marking" do
      entity = Reactive.mark_dodging_target(warrior(class: 4), 77, 1_000)

      assert entity.player.combo_points in [nil, 0]
    end

    test "tick expires the combo point" do
      entity = warrior() |> Reactive.mark_dodging_target(77, 1_000) |> Reactive.tick(5_000)

      assert entity.player.combo_points == 0
      assert entity.player.field_combo_target == 77
      assert entity.internal.combo_expires_at == nil
    end

    test "consume clears the combo point immediately" do
      entity = warrior() |> Reactive.mark_dodging_target(77, 1_000) |> Reactive.consume_combo()

      refute Reactive.combo_active?(entity, 77, 1_500)
    end
  end
end
