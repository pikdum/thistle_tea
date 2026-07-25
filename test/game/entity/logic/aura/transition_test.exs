defmodule ThistleTea.Game.Entity.Logic.Aura.TransitionTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, <<<: 2]

  alias ThistleTea.Game.Aura, as: AuraData
  alias ThistleTea.Game.Aura.Holder
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Aura.Change
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Spell

  @movement_flag_root 0x08000000
  @unit_vis_creep 0x02
  @player_flag_stealth 0x20

  describe "transition/2" do
    test "reconciles identical removals consistently for every cause" do
      holder = projection_holder()

      {active, _events} =
        Aura.transition(character(), %Change{holders: [holder], cause: :applied, now: 1_000})

      assert active.object.scale_x == 1.5
      assert active.unit.normal_resistance == 27
      assert active.player.track_creatures == 1 <<< 1
      assert (active.unit.vis_flag &&& @unit_vis_creep) != 0
      assert (active.player.field_bytes2_flags &&& @player_flag_stealth) != 0
      assert (active.movement_block.movement_flags &&& @movement_flag_root) != 0
      assert active.internal.rooted?

      results =
        Enum.map(Change.causes(), fn cause ->
          {entity, events} =
            Aura.transition(active, %Change{holders: [], cause: cause, now: 2_000})

          {projection(entity), events}
        end)

      assert results |> Enum.map(&elem(&1, 0)) |> Enum.uniq() == [
               {[], 1.0, 7, 0, 0, 0, 0, false}
             ]

      assert results |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length() == 1

      assert Enum.all?(results, fn {_projection, events} ->
               Enum.any?(events, &match?(%Effects.MovementRootChanged{rooted?: false}, &1))
             end)
    end

    test "assigns polarity slots while keeping nonvisual passives hidden" do
      hidden =
        holder(1, false, [
          %AuraData{type: :add_flat_modifier, amount: 1, misc_value: 0, class_mask: 1}
        ])

      hidden = %{hidden | spell: %{hidden.spell | attributes: MapSet.new([:passive])}}
      positive = holder(2, false, [])
      negative = holder(3, true, [])

      {entity, _events} =
        Aura.transition(
          character(),
          %Change{holders: [hidden, positive, negative], cause: :applied, now: 1_000}
        )

      assert Enum.map(entity.unit.auras, & &1.slot) == [nil, 0, 32]
    end

    test "runs expiration-only removal hooks only for expiration" do
      spirit =
        holder(27_795, false, [%AuraData{type: :spirit_of_redemption}])
        |> then(&%{&1 | caster_guid: 1, caster_level: 60})

      {active, _events} =
        Aura.transition(character(), %Change{holders: [spirit], cause: :applied, now: 1_000})

      results =
        Map.new(Change.causes(), fn cause ->
          {_entity, events} =
            Aura.transition(active, %Change{holders: [], cause: cause, now: 2_000})

          triggered? =
            Enum.any?(events, fn
              %Effects.TriggerSpell{spell_id: 27_965} -> true
              _event -> false
            end)

          {cause, triggered?}
        end)

      assert results.expired
      assert results |> Map.delete(:expired) |> Map.values() |> Enum.all?(&(&1 == false))
    end
  end

  defp character do
    %Character{
      object: %Object{guid: 1, base_scale_x: 1.0, scale_x: 1.0},
      unit: %Unit{
        level: 60,
        health: 100,
        max_health: 100,
        auras: [],
        base_normal_resistance: 7,
        normal_resistance: 7,
        vis_flag: 0,
        dynamic_flags: 0,
        flags: 0
      },
      player: %Player{
        track_creatures: 0,
        field_bytes_flags: 0,
        field_bytes2_flags: 0
      },
      internal: %Internal{},
      movement_block: %MovementBlock{
        position: {0.0, 0.0, 0.0, 0.0},
        movement_flags: 0,
        base_run_speed: 7.0,
        run_speed: 7.0
      }
    }
  end

  defp projection_holder do
    holder(100, false, [
      %AuraData{type: :mod_scale, amount: 50},
      %AuraData{type: :mod_resistance, amount: 20, misc_value: 1},
      %AuraData{type: :track_creatures, misc_value: 2},
      %AuraData{type: :mod_stealth},
      %AuraData{type: :mod_root}
    ])
  end

  defp holder(id, negative?, auras) do
    %Holder{
      spell: %Spell{id: id, aura_interrupt_flags: 0, effects: []},
      caster_guid: 1,
      caster_level: 60,
      applied_at: 1_000,
      auras: auras,
      negative?: negative?
    }
  end

  defp projection(entity) do
    {
      entity.unit.auras,
      entity.object.scale_x,
      entity.unit.normal_resistance,
      entity.player.track_creatures,
      entity.unit.vis_flag &&& @unit_vis_creep,
      entity.player.field_bytes2_flags &&& @player_flag_stealth,
      entity.movement_block.movement_flags &&& @movement_flag_root,
      entity.internal.rooted?
    }
  end
end
