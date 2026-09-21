defmodule ThistleTea.Game.Entity.Logic.Aura.AurasVisibleTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [&&&: 2, |||: 2]

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Network.UpdateObject
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.Effect

  @auras_visible 0x08000000
  @pvp_attackable 0x00000008

  setup [:targets]

  describe "apply_spell/4" do
    test "reveals creature and player buffs to observers", %{targets: targets} do
      for entity <- targets do
        {revealed, _events} = apply_detect_magic(entity, 10, detect_magic(), 1_000)

        assert revealed.internal.broadcast_update?
        assert revealed.unit.flags == (@pvp_attackable ||| @auras_visible)
        assert [%{negative?: true, slot: 32}] = revealed.unit.auras
        assert observer_flags(revealed) == <<@pvp_attackable ||| @auras_visible::little-size(32)>>

        {refreshed, _events} = apply_detect_magic(revealed, 10, detect_magic(), 60_000)
        {refreshed, _events} = Aura.expire_due(refreshed, 121_000)
        assert (refreshed.unit.flags &&& @auras_visible) != 0

        {expired, _events} = Aura.expire_due(refreshed, 180_000)
        assert expired.unit.auras == []
        assert observer_flags(expired) == <<@pvp_attackable::little-size(32)>>
      end
    end

    test "keeps reveal until the last source ends", %{targets: [entity | _]} do
      {entity, _events} = apply_detect_magic(entity, 10, detect_magic(), 1_000)
      second = %{detect_magic() | id: 1852}
      {entity, _events} = apply_detect_magic(entity, 11, second, 2_000)
      assert length(entity.unit.auras) == 2

      {entity, _events} = Aura.remove_source_spell(entity, 2855, 10, 3_000)
      assert (entity.unit.flags &&& @auras_visible) != 0

      {entity, _events} = Aura.expire_due(entity, 122_000)
      assert entity.unit.flags == @pvp_attackable
    end
  end

  describe "dispel/5" do
    test "clears the reveal and broadcasts its removal", %{targets: targets} do
      for entity <- targets do
        {entity, _events} = apply_detect_magic(entity, 10, detect_magic(), 1_000)
        entity = %{entity | internal: %{entity.internal | broadcast_update?: false}}
        {entity, _events} = Aura.dispel(entity, 1, 2_000, :negative)

        assert entity.unit.auras == []
        assert entity.unit.flags == @pvp_attackable
        assert entity.internal.broadcast_update?
      end
    end
  end

  describe "take_damage/4" do
    test "death removes the reveal through the shared lifecycle", %{targets: targets} do
      for entity <- targets do
        {entity, _events} = apply_detect_magic(entity, 10, detect_magic(), 1_000)
        entity = Core.take_damage(entity, 100, 2_000, environmental: true)

        assert entity.unit.health == 0
        refute Aura.has_aura?(entity, :auras_visible)
        assert (entity.unit.flags &&& @auras_visible) == 0
      end
    end
  end

  describe "sync_unit/1" do
    test "rebuilds stale reveal flags when no holders remain" do
      for holders <- [nil, []] do
        unit = Aura.sync_unit(%Unit{flags: @pvp_attackable ||| @auras_visible, auras: holders})
        assert unit.flags == @pvp_attackable
      end
    end
  end

  defp targets(_context) do
    unit = %Unit{health: 100, max_health: 100, level: 60, flags: @pvp_attackable, auras: []}
    object = %Object{guid: 1}
    movement = %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}

    %{
      targets: [
        %Mob{object: object, unit: unit, internal: %Internal{}, movement_block: movement},
        %Character{object: object, unit: unit, player: %Player{}, internal: %Internal{}, movement_block: movement}
      ]
    }
  end

  defp detect_magic do
    %Spell{
      id: 2855,
      duration_ms: 120_000,
      dispel_type: 1,
      effects: [%Effect{index: 0, type: :apply_aura, aura: :auras_visible, implicit_target_a: :target_enemy}]
    }
  end

  defp observer_flags(entity) do
    entity.unit |> Unit.to_list(:other) |> List.keyfind(:flags, 0) |> UpdateObject.field()
  end

  defp apply_detect_magic(entity, caster_guid, spell, now) do
    context = %CastContext{
      caster_guid: caster_guid,
      caster_level: 60,
      target_guid: entity.object.guid,
      target_hostile?: true,
      spell: spell
    }

    Aura.apply_spell(entity, context, spell, now)
  end
end
