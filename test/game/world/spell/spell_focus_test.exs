defmodule ThistleTea.Game.World.Spell.SpellFocusTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Core.Effects
  alias ThistleTea.Game.Core.Entity.Character
  alias ThistleTea.Game.Core.Entity.Component.Internal
  alias ThistleTea.Game.Core.Entity.Component.MovementBlock
  alias ThistleTea.Game.Core.Entity.Component.Object
  alias ThistleTea.Game.Core.Entity.Component.Player
  alias ThistleTea.Game.Core.Entity.Component.Unit
  alias ThistleTea.Game.Core.Entity.GameObject
  alias ThistleTea.Game.Core.Entity.GameObjectTemplate
  alias ThistleTea.Game.Core.Entity.Mob
  alias ThistleTea.Game.Core.Spell
  alias ThistleTea.Game.Core.Spell.Cast
  alias ThistleTea.Game.Core.Spell.Casting
  alias ThistleTea.Game.Core.Spell.CastValidation
  alias ThistleTea.Game.Core.Spell.Focus
  alias ThistleTea.Game.Core.Spell.Requirements
  alias ThistleTea.Game.Core.Spell.Target
  alias ThistleTea.Game.Core.WorldRef
  alias ThistleTea.Game.Network.Message.SmsgCastResult
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Entity
  alias ThistleTea.Game.World.Entity.EventSink
  alias ThistleTea.Game.World.Entity.EventSink.Context
  alias ThistleTea.Game.World.Loader.GameObjectTemplate, as: GameObjectTemplateLoader
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.Spell.SpellFocus

  setup [:focus_templates]

  describe "find/2" do
    test "matches identity, type, spawn state and instance", %{caster: caster, spell: spell, focus: focus} do
      wrong = %{focus | entry: 951_002, data: [50_002, 5]}
      generic = %{focus | entry: 951_003, type: 5}
      spawn_object(wrong, caster.internal.world, {0.0, 0.0, 0.0, 0.0})
      spawn_object(generic, caster.internal.world, {0.0, 0.0, 0.0, 0.0})
      spawn_object(focus, WorldRef.instance(999, 2), {0.0, 0.0, 0.0, 0.0})
      assert SpellFocus.find(caster, spell) == nil

      object = spawn_object(focus, caster.internal.world, {1.0, 0.0, 0.0, 0.0})
      guid = object.object.guid
      assert %Focus{guid: ^guid, id: 50_001} = SpellFocus.find(caster, spell)
      Metadata.update(guid, %{go_spawned?: false})
      assert SpellFocus.find(caster, spell) == nil
      Metadata.update(guid, %{go_spawned?: true})
      assert %Focus{guid: ^guid} = SpellFocus.find(caster, spell)
      World.stop_entity(guid)
      assert SpellFocus.find(caster, spell) == nil
    end

    test "uses three-dimensional template distance and bounding radii", %{caster: caster, spell: spell, focus: focus} do
      object = spawn_object(focus, caster.internal.world, {0.0, 0.0, 5.78, 0.0})
      assert %Focus{} = SpellFocus.find(caster, spell)
      object = %{object | movement_block: %{object.movement_block | position: {0.0, 0.0, 5.80, 0.0}}}
      World.update_position(object)
      assert SpellFocus.find(caster, spell) == nil
    end

    test "finds long-range focus templates and chooses the nearest valid object", context do
      %{caster: caster, spell: spell, focus: focus} = context
      long = %{focus | entry: 951_004, data: [50_001, 100]}
      far = spawn_object(long, caster.internal.world, {80.0, 0.0, 0.0, 0.0})
      assert SpellFocus.find(caster, spell).guid == far.object.guid
      near = spawn_object(focus, caster.internal.world, {3.0, 0.0, 0.0, 0.0})
      assert SpellFocus.find(caster, spell).guid == near.object.guid
    end
  end

  describe "validate/6" do
    test "requires the matching focus before starting a cast", %{caster: caster, spell: spell} do
      targets = Target.self(caster.object.guid)
      assert {:error, :requires_spell_focus} = CastValidation.validate(caster, spell, targets, nil, 0)

      assert {:error, :requires_spell_focus} =
               CastValidation.validate(caster, spell, targets, nil, 0, spell_focus: %Focus{id: 50_002})

      assert :ok =
               CastValidation.validate(caster, spell, targets, nil, 0,
                 spell_focus: %Focus{id: 50_001},
                 count_item: fn _ -> 1 end
               )

      assert :ok = CastValidation.validate(caster, %{spell | required_focus_id: 0, reagents: []}, targets, nil, 0)
    end

    test "exempts passive spells and creature casts as the reference does", %{caster: caster, spell: spell} do
      assert :ok = Focus.validate(caster, %{spell | attributes: MapSet.new([:passive])}, nil)
      assert :ok = Focus.validate(%Mob{}, spell, nil)
    end
  end

  describe "complete/2" do
    test "rechecks a lost focus without charging power, reagents or cooldown", context do
      %{caster: caster, spell: spell, focus: focus} = context
      object = spawn_object(focus, caster.internal.world, {1.0, 0.0, 0.0, 0.0})
      assert %Focus{} = SpellFocus.find(caster, spell)
      started = Casting.start(caster, spell, Target.self(caster.object.guid), 1_000)
      World.stop_entity(object.object.guid)

      completed = started |> Casting.complete(2_000) |> EventSink.emit_pending(Context.new(self()))
      assert completed.internal.casting == nil
      assert completed.unit.power1 == caster.unit.power1
      assert completed.internal.cooldowns == started.internal.cooldowns

      assert_receive {:"$gen_cast",
                      {:send_packet, %SmsgCastResult{reason: 0x5E, required_spell_focus: 50_001} = failure}}

      assert SmsgCastResult.to_binary(failure) == <<951_010::little-size(32), 2, 0x5E, 50_001::little-size(32)>>
      refute_receive {:consume_reagents, _}
    end

    test "launches once after successful boundary revalidation", %{caster: caster, spell: spell, focus: focus} do
      spawn_object(focus, caster.internal.world, {1.0, 0.0, 0.0, 0.0})
      started = Casting.start(caster, spell, Target.self(caster.object.guid), 1_000)
      ready = Casting.complete(started, 2_000)
      assert [%Effects.CheckCastRequirements{}] = ready.internal.events
      completed = EventSink.emit_pending(ready, Context.new(self()))
      assert completed.internal.casting == nil
      assert completed.unit.power1 == 90
      assert_receive {:consume_reagents, [{2770, 1}]}
      refute_receive {:consume_reagents, _}
      assert_receive {:"$gen_cast", {:send_packet, %SmsgCastResult{spell: 951_010, result: 0}}}
    end
  end

  describe "resolve_requirements/4" do
    test "ignores a result belonging to a cancelled or replaced cast", %{caster: caster, spell: spell} do
      started = Casting.start(caster, spell, Target.self(caster.object.guid), 1_000)
      pending = Casting.complete(started, 2_000)
      cast = pending.internal.casting
      cancelled = Casting.cancel(pending, 2_000)
      assert Casting.resolve_requirements(cancelled, cast, %Requirements{focus: %Focus{id: 50_001}}, 2_000) == cancelled
      replacement = %{cancelled | internal: %{cancelled.internal | casting: Cast.new(spell, Target.none(), 3_000)}}
      assert Casting.resolve_requirements(replacement, cast, %Requirements{}, 3_000) == replacement
    end
  end

  defp focus_templates(_context) do
    focus = %GameObjectTemplate{entry: 951_001, type: 8, size: 1.0, faction: 0, flags: 0, data: [50_001, 5]}

    caster = %Character{
      object: %Object{guid: 951_100},
      player: %Player{},
      unit: %Unit{level: 10, health: 100, power1: 100, max_power1: 100, power_type: 0, bounding_radius: 0.4},
      internal: %Internal{world: WorldRef.instance(999, 1)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    }

    spell = %Spell{
      id: 951_010,
      name: "Focus craft",
      required_focus_id: 50_001,
      cast_time_ms: 1_000,
      power_type: 0,
      mana_cost: 10,
      recovery_time_ms: 5_000,
      reagents: [{2770, 1}]
    }

    on_exit(fn ->
      for entry <- 951_001..951_004, do: :ets.delete(GameObjectTemplateLoader, entry)
      for id <- [50_001, 50_002], do: :ets.delete(GameObjectTemplateLoader, {:focus_radius, id})
    end)

    %{caster: caster, spell: spell, focus: focus}
  end

  defp spawn_object(template, world, position) do
    GameObjectTemplateLoader.put(template)
    object = GameObject.build_summoned(template, world, position)
    {:ok, _pid} = World.start_entity(object)

    on_exit(fn ->
      if Entity.pid(object.object.guid), do: World.stop_entity(object.object.guid)
    end)

    object
  end
end
