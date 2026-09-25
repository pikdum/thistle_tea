defmodule ThistleTea.Game.Entity.Logic.ReactiveTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Aura
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Death
  alias ThistleTea.Game.Entity.Logic.Reactive
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Effect

  @defense_bit 0x1
  @healthless_bit 0x2
  @judgement_bit 0x10
  @hunter_parry_bit 0x40

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
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}},
      internal: %Internal{}
    }
  end

  describe "receive_attack/4" do
    test "ordinary swings project class-specific avoidance windows" do
      for {class, outcome, bits} <- [{3, :dodge, 1}, {3, :parry, 0x40}, {4, :dodge, 0}, {4, :parry, 1}] do
        entity = warrior(class: class)
        dodge = if outcome == :dodge, do: 100, else: -100

        holder = %Holder{
          spell: %Spell{id: 1},
          auras: [%Aura{type: :mod_dodge, amount: dodge}, %Aura{type: :mod_parry_percent, amount: 100}]
        }

        entity = %{
          entity
          | unit: %{entity.unit | sheath_state: 1, auras: [holder]},
            player: %{entity.player | visible_item_16_0: 1},
            internal: %{entity.internal | spellbook: %{3127 => %Spell{id: 3127, effects: [%Effect{type: :parry}]}}}
        }

        {entity, events} =
          Combat.receive_attack(entity, %{caster: 77, damage: 10, caster_level: 10, hit_chance_bonus: 100}, 1_000,
            roll: 100
          )

        assert Enum.any?(events, &match?(%{outcome: ^outcome}, &1))
        assert entity.unit.health == 100
        assert entity.unit.aura_state == bits
      end
    end
  end

  describe "mark_defense/4" do
    test "sets the defense aura-state bit for four seconds" do
      entity = Reactive.mark_defense(warrior(), 77, :block, 1_000)

      assert Bitwise.band(entity.unit.aura_state, @defense_bit) == @defense_bit
      assert Reactive.defense_active?(entity, 4_999)
      refute Reactive.defense_active?(entity, 5_000)
    end

    test "tick clears the bit after the window" do
      entity = warrior() |> Reactive.mark_defense(77, :block, 1_000) |> Reactive.tick(5_000)

      assert Bitwise.band(entity.unit.aura_state, @defense_bit) == 0
    end

    test "ignores non-players" do
      mob = %Mob{unit: %Unit{health: 100, max_health: 100}, internal: %Internal{}}

      assert Reactive.mark_defense(mob, 77, :dodge, 1_000) == mob
    end

    test "hunter dodge and parry retain independent targets and deadlines" do
      hunter =
        warrior(class: 3)
        |> Reactive.mark_defense(77, :dodge, 1_000)
        |> Reactive.mark_defense(78, :parry, 2_000)

      assert hunter.unit.aura_state == @defense_bit + @hunter_parry_bit
      assert hunter.player.field_combo_target == 78
      assert hunter.player.combo_points == 1
      assert Reactive.target_active?(hunter, :defense, 77, 4_999)
      assert Reactive.target_active?(hunter, :hunter_parry, 78, 4_999)
      refute Reactive.target_active?(hunter, :defense, 78, 4_999)
      refute Reactive.target_active?(hunter, :hunter_parry, 77, 4_999)

      hunter = Reactive.tick(hunter, 5_000)
      assert hunter.unit.aura_state == @hunter_parry_bit
      assert hunter.internal.defense_window == nil
      assert Reactive.target_active?(hunter, :hunter_parry, 78, 5_999)

      hunter = Reactive.tick(hunter, 6_000)
      assert hunter.unit.aura_state == 0
      assert hunter.internal.hunter_parry_window == nil
      assert hunter.player.field_combo_target == 78
    end

    test "refreshing hunter dodge preserves the earlier parry window" do
      hunter =
        warrior(class: 3)
        |> Reactive.mark_defense(77, :dodge, 1_000)
        |> Reactive.mark_defense(78, :parry, 2_000)
        |> Reactive.mark_defense(79, :dodge, 3_000)
        |> Reactive.tick(6_000)

      assert hunter.unit.aura_state == @defense_bit
      refute Reactive.target_active?(hunter, :defense, 77, 6_000)
      assert Reactive.target_active?(hunter, :defense, 79, 6_999)
      refute Reactive.target_active?(hunter, :defense, 79, 7_000)
    end

    test "rogue dodge neither opens nor refreshes Riposte" do
      rogue = warrior(class: 4) |> Reactive.mark_defense(77, :dodge, 1_000)
      refute Reactive.defense_active?(rogue, 1_000)
      assert rogue.unit.aura_state == 0

      rogue =
        rogue
        |> Reactive.mark_defense(77, :parry, 2_000)
        |> Reactive.mark_defense(78, :dodge, 3_000)

      assert Reactive.target_active?(rogue, :defense, 77, 5_999)
      refute Reactive.defense_active?(rogue, 6_000)
    end

    test "warrior avoidance shares the Revenge window" do
      for outcome <- [:dodge, :parry, :block] do
        entity = Reactive.mark_defense(warrior(), 77, outcome, 1_000)
        assert entity.unit.aura_state == @defense_bit
        assert Reactive.target_active?(entity, :defense, 77, 4_999)
      end
    end

    test "dead players cannot open defensive windows" do
      for class <- [1, 3, 4], outcome <- [:dodge, :parry, :block] do
        entity = warrior(class: class, health: 0)
        assert Reactive.mark_defense(entity, 77, outcome, 1_000) == entity
      end
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
      entity = warrior() |> Reactive.mark_defense(77, :block, 1_000)
      entity = %{entity | unit: %{entity.unit | health: 10}}

      assert Reactive.sync_health(entity).unit.aura_state == @defense_bit + @healthless_bit
    end

    test "reactive sync preserves aura-owned state bits" do
      entity = warrior()
      entity = %{entity | unit: %{entity.unit | aura_state: @judgement_bit}}

      assert Reactive.sync(entity, 1_000).unit.aura_state == @judgement_bit
    end
  end

  describe "clear/2" do
    test "clears windows and combo markers while preserving unrelated aura states" do
      hunter =
        warrior(class: 3, health: 10)
        |> Reactive.mark_defense(77, :dodge, 1_000)
        |> Reactive.mark_defense(78, :parry, 1_000)

      hunter = %{hunter | unit: %{hunter.unit | aura_state: hunter.unit.aura_state + @judgement_bit}}
      hunter = Reactive.clear(hunter, 2_000)

      assert hunter.internal.defense_window == nil
      assert hunter.internal.hunter_parry_window == nil
      assert hunter.internal.combo_target_guid == nil
      assert hunter.player.combo_points == 0
      assert hunter.unit.aura_state == @healthless_bit + @judgement_bit
      assert hunter.internal.broadcast_update?
    end

    test "lethal damage clears windows before expiry and resurrection cannot restore them" do
      hunter =
        warrior(class: 3)
        |> Reactive.mark_defense(77, :dodge, 1_000)
        |> Reactive.mark_defense(78, :parry, 1_000)
        |> Core.take_damage(100, 2_000)

      assert hunter.unit.health == 0
      assert hunter.unit.aura_state == 0
      assert hunter.internal.defense_window == nil
      assert hunter.internal.hunter_parry_window == nil
      assert hunter.player.combo_points == 0

      {hunter, _events} = Death.resurrect(hunter, 100, 3_000)
      refute Reactive.defense_active?(hunter, 3_000)
      refute Reactive.active?(hunter, :hunter_parry, 3_000)
      assert hunter.unit.aura_state == 0
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
