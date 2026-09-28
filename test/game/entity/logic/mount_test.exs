defmodule ThistleTea.Game.Entity.Logic.MountTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Player
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Model
  alias ThistleTea.Game.Entity.Data.Taxi.Flight
  alias ThistleTea.Game.Entity.Logic.Aura
  alias ThistleTea.Game.Entity.Logic.Casting
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Logic.Mount
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Spell.Area
  alias ThistleTea.Game.Spell.Cast
  alias ThistleTea.Game.Spell.CastContext
  alias ThistleTea.Game.Spell.CastValidation
  alias ThistleTea.Game.Spell.Effect
  alias ThistleTea.Game.Spell.Requirements
  alias ThistleTea.Game.Spell.Target
  alias ThistleTea.Game.WorldRef

  setup [:character]

  describe "apply_spell/5" do
    test "Discombobulate dismounts and restores appearance without restoring the mount", %{character: c} do
      {mounted, _} = apply_spell(c, mount(1, 2404, 100))
      {mounted, _} = apply_spell(mounted, %{buff(4, :dummy, 1) | aura_interrupt_flags: 0x40})
      {changed, events} = Aura.apply_spell(mounted, 2, 60, discombobulate(), 2_000)
      assert changed.unit.mount_display_id == 0
      assert changed.unit.display_id == 100
      assert_in_delta changed.movement_block.run_speed, 5.6, 0.00001
      refute Aura.has_spell?(changed, 1)
      refute Aura.has_spell?(changed, 4)
      assert Enum.any?(events, &match?(%Effects.MovementSpeedChanged{movement_type: :run_speed}, &1))
      {expired, _} = Aura.expire_due(changed, 7_000)
      assert expired.unit.display_id == c.unit.native_display_id
      assert expired.unit.mount_display_id == 0
      assert expired.movement_block.run_speed == 7.0
    end

    test "only a new Discombobulate transformation interrupts a mount", %{character: c} do
      {changed, _} = apply_spell(c, discombobulate())
      {mounted, _} = apply_spell(changed, mount(1, 2404, 100))
      {unchanged, _} = apply_spell(mounted, buff(4, :dummy, 1))
      assert unchanged.unit.mount_display_id == 2404
      {refreshed, _} = Aura.apply_spell(unchanged, 1, 60, discombobulate(), 2_000)
      assert refreshed.unit.mount_display_id == 0
      costume = %{discombobulate() | id: 900_001}
      {costumed, _} = Aura.apply_spell(mounted, 2, 60, costume, 2_000)
      assert costumed.unit.mount_display_id == 2404
    end

    test "mounts and cancels through the aura lifecycle", %{character: character} do
      {mounted, _events} = apply_spell(character, mount(1, 2404, 60))
      assert mounted.unit.mount_display_id == 2404
      assert_in_delta mounted.movement_block.run_speed, 11.2, 0.00001
      assert mounted.movement_block.run_back_speed == character.movement_block.run_back_speed
      assert mounted.movement_block.swim_speed == character.movement_block.swim_speed

      {dismounted, _events} = Aura.cancel_spell(mounted, 1, 2000)
      assert dismounted.unit.mount_display_id == 0
      assert dismounted.movement_block.run_speed == 7.0
    end

    test "replaces another mount without resurrecting it on cancel", %{character: character} do
      {mounted, _events} = apply_spell(character, mount(1, 2404, 60))
      {mounted, _events} = apply_spell(mounted, mount(2, 14_337, 100))
      assert mounted.unit.mount_display_id == 14_337
      assert mounted.movement_block.run_speed == 14.0
      refute Aura.has_spell?(mounted, 1)
      {dismounted, _events} = Aura.cancel_spell(mounted, 2, 2000)
      assert dismounted.unit.mount_display_id == 0
      assert dismounted.movement_block.run_speed == 7.0
    end

    test "uses mounted bonuses instead of foot speed and applies snares", %{character: character} do
      {character, _events} = apply_spell(character, buff(3, :mod_increase_speed, 100))
      {mounted, _events} = apply_spell(character, mount(1, 2404, 60))
      assert_in_delta mounted.movement_block.run_speed, 11.2, 0.00001
      {mounted, _events} = apply_spell(mounted, buff(4, :mod_decrease_speed, -50))
      assert_in_delta mounted.movement_block.run_speed, 5.6, 0.00001
      {dismounted, _events} = Aura.cancel_spell(mounted, 1, 2000)
      assert dismounted.movement_block.run_speed == 7.0
    end

    test "multiplies mounted equipment bonuses and compares the nonstacking bonus", %{character: character} do
      {mounted, _events} = apply_spell(character, mount(1, 2404, 100))
      {mounted, _events} = apply_spell(mounted, buff(3, :mod_mounted_speed_always, 3))
      {mounted, _events} = apply_spell(mounted, buff(4, :mod_mounted_speed_always, 2))
      assert_in_delta mounted.movement_block.run_speed, 14 * 1.03 * 1.02, 0.00001
      {mounted, _events} = apply_spell(mounted, buff(5, :mod_mounted_speed_not_stack, 10))
      assert_in_delta mounted.movement_block.run_speed, 15.4, 0.00001
      {dismounted, _events} = Aura.cancel_spell(mounted, 1, 2000)
      assert dismounted.movement_block.run_speed == 7.0
    end

    test "death removes the mount and restores speed", %{character: character} do
      {mounted, _events} = apply_spell(character, mount(1, 2404, 60))
      dead = Core.take_damage(mounted, 100, 2000)
      assert dead.unit.health == 0
      assert dead.unit.mount_display_id == 0
      assert dead.movement_block.run_speed == 7.0
    end

    test "unrelated aura changes preserve a script mount display", %{character: character} do
      character = %{character | unit: %{character.unit | mount_display_id: 2404}}
      {character, _events} = apply_spell(character, buff(3, :mod_increase_speed, 50))
      assert character.unit.mount_display_id == 2404
    end

    test "mounting and dismounting honor aura interruption flags", %{character: character} do
      {character, _events} = apply_spell(character, %{buff(3, :dummy, 1) | aura_interrupt_flags: 0x20000})
      {mounted, _events} = apply_spell(character, mount(1, 2404, 60))
      refute Aura.has_spell?(mounted, 3)
      {mounted, _events} = apply_spell(mounted, %{buff(4, :dummy, 1) | aura_interrupt_flags: 0x40})
      dismounted = Mount.dismount(mounted, 2000)
      refute Aura.has_spell?(dismounted, 4)
    end

    test "entering water removes the mount through its interrupt flags", %{character: character} do
      spell = %{mount(1, 2404, 60) | aura_interrupt_flags: 0x80}
      {mounted, _events} = apply_spell(character, spell)
      {dismounted, _events} = Aura.remove_with_interrupt_flags(mounted, Aura.interrupt_mask(:under_water), 2000)
      assert dismounted.unit.mount_display_id == 0
      assert dismounted.movement_block.run_speed == 7.0
    end
  end

  describe "receive/4" do
    test "Holly replaces each mount speed tier through one triggered self cast", %{character: c} do
      for {speed, expected} <- [{60, 25_858}, {100, 25_859}] do
        {mounted, _} = apply_spell(c, mount(1, 2404, speed))
        context = %CastContext{caster_guid: 1, caster_level: 60, cast_item_guid: 123}
        {changed, events} = SpellEffect.receive(mounted, context, holly(), 2_000)
        assert changed.unit.mount_display_id == 0
        refute Aura.has_aura?(changed, :mounted)

        assert [%Effects.TriggerSpell{source_guid: 1, target_guid: 1, spell_id: ^expected, cast_item_guid: 123}] =
                 Enum.filter(events, &is_struct(&1, Effects.TriggerSpell))

        {reindeer, _} = apply_spell(changed, mount(expected, 15_960, speed))
        assert reindeer.unit.mount_display_id == 15_960
        assert reindeer.movement_block.run_speed == mounted.movement_block.run_speed
        {cancelled, _} = Aura.cancel_spell(reindeer, expected, 3_000)
        assert cancelled.unit.mount_display_id == 0
        assert cancelled.movement_block.run_speed == 7.0
        assert cancelled.unit.auras == []
      end
    end

    test "Holly chooses its speed tier before removing the old mount", %{character: c} do
      {mounted, _} = apply_spell(c, mount(1, 2404, 100))
      {slowed, _} = apply_spell(mounted, buff(4, :mod_decrease_speed, -20))
      {_, events} = SpellEffect.receive(slowed, 1, holly(), 2_000)
      assert Enum.any?(events, &match?(%Effects.TriggerSpell{spell_id: 25_858}, &1))
    end

    test "Holly has no effect after dismounting or when delivered to another target", %{character: c} do
      assert {^c, []} = SpellEffect.receive(c, 1, holly(), 2_000)
      {mounted, _} = apply_spell(c, mount(1, 2404, 100))
      assert {^mounted, []} = SpellEffect.receive(mounted, 2, holly(), 2_000)
    end

    test "transform immunity retains the mount while the Discombobulate slow lands", %{character: c} do
      {mounted, _} = apply_spell(c, mount(1, 2404, 100))

      immunity = %Spell{
        id: 900_001,
        effects: [%Effect{index: 0, type: :apply_aura, aura: :state_immunity, misc_value: :transform}]
      }

      {protected, _} = apply_spell(mounted, immunity)
      {changed, _} = SpellEffect.receive(protected, 2, discombobulate(), 2_000)
      assert changed.unit.mount_display_id == 2404
      assert changed.unit.display_id == c.unit.display_id
      assert_in_delta changed.movement_block.run_speed, 11.2, 0.00001
    end
  end

  describe "start/4" do
    test "ordinary casts dismount without losing their speed-change effects", %{character: character} do
      {mounted, _events} = apply_spell(character, mount(1, 2404, 60))
      casting = Casting.start(mounted, buff(3, :dummy, 1), Target.self(1), 2000)
      assert casting.unit.mount_display_id == 0
      assert casting.movement_block.run_speed == 7.0
      assert casting.internal.casting.spell.id == 3
      refute casting.internal.events == []
    end

    test "allowed casts preserve the mount", %{character: character} do
      {mounted, _events} = apply_spell(character, mount(1, 2404, 60))
      spell = %{buff(3, :dummy, 1) | attributes: MapSet.new([:allow_while_mounted])}
      casting = Casting.start(mounted, spell, Target.self(1), 2000)
      assert casting.unit.mount_display_id == 2404
    end
  end

  describe "validate/3" do
    test "area-bound mounts bypass the map ban after their area requirement passes", %{character: c} do
      spell = %{mount(25_953, 15_903, 100) | area_rules: [%Area{area_id: 3428}]}
      opts = [mount_context: %Mount.Context{mount_allowed?: false}, spell_area: %Area.Context{area_id: 3428}]
      assert CastValidation.validate(c, spell, Target.self(1), nil, 2_000, opts) == :ok

      assert CastValidation.validate(
               c,
               spell,
               Target.self(1),
               nil,
               2_000,
               Keyword.put(opts, :spell_area, %Area.Context{area_id: 1519})
             ) == {:error, :requires_area}

      quest_only = %{spell | area_rules: [%Area{quest_start: 1}]}
      assert Mount.validate(c, quest_only, opts) == {:error, :no_mounts_allowed}
    end

    test "Black Qiraji is allowed in its temple and ordinary mount maps", %{character: c} do
      assert Mount.validate(c, qiraji(), []) == :ok
      blocked = [mount_context: %Mount.Context{mount_allowed?: false}]
      assert Mount.validate(c, qiraji(), blocked) == {:error, :no_mounts_allowed}
      temple = %{c | internal: %{c.internal | world: WorldRef.instance(531, 1)}}
      assert Mount.validate(temple, qiraji(), blocked) == :ok
      assert Mount.validate(temple, mount(1, 2404, 100), blocked) == {:error, :no_mounts_allowed}
      assert Mount.validate(c, qiraji(), Keyword.put(blocked, :triggered?, true)) == :ok
      swimming = %{c | movement_block: %{c.movement_block | movement_flags: 0x00200000}}
      assert Mount.validate(swimming, qiraji(), []) == {:error, :only_abovewater}
    end

    test "transports distinguish exposed decks and the Black Qiraji restriction", %{character: c} do
      passenger = %{c | movement_block: %{c.movement_block | transport_guid: 123}}

      for outdoors <- [nil, false] do
        assert Mount.validate(passenger, mount(1, 2404, 100), mount_context: %Mount.Context{outdoors?: outdoors}) ==
                 {:error, :no_mounts_allowed}
      end

      deck = [mount_context: %Mount.Context{outdoors?: true}]
      assert Mount.validate(passenger, mount(1, 2404, 100), deck) == :ok
      assert Mount.validate(passenger, qiraji(), deck) == {:error, :no_mounts_allowed}

      assert Mount.validate(c, mount(1, 2404, 100), mount_context: %Mount.Context{area_id: 35}) ==
               {:error, :no_mounts_allowed}
    end

    test "mounts reject animal forms and models that cannot ride", %{character: c} do
      for form <- [1, 3, 4, 5, 8, 16, 31, 32] do
        shifted = %{c | unit: %{c.unit | shapeshift_form: form}}
        assert Mount.validate(shifted, qiraji(), []) == {:error, :not_shapeshift}
      end

      for form <- [0, 17, 18, 19, 28, 30] do
        shifted = %{c | unit: %{c.unit | shapeshift_form: form}}
        assert Mount.validate(shifted, qiraji(), []) == :ok
      end

      transformed = %{c | unit: %{c.unit | display_id: 7550}}
      assert Mount.validate(transformed, qiraji(), []) == {:error, :not_shapeshift}
      assert Mount.validate(transformed, qiraji(), mount_context: %Mount.Context{display_mountable?: true}) == :ok
    end

    test "Holly requires an aura-owned mount before casting or spending its item", %{character: c} do
      spell = holly()
      assert CastValidation.validate(c, spell, Target.self(1), nil, 2_000) == {:error, :only_mounted}
      {mounted, _} = apply_spell(c, mount(1, 2404, 60))
      assert Mount.validate(mounted, spell, []) == :ok
      casting = Casting.start(mounted, spell, Target.self(1), 2_000)
      assert casting.unit.mount_display_id == 2404
      script_mount = %{c | unit: %{c.unit | mount_display_id: 2404}}
      assert Mount.validate(script_mount, spell, []) == {:error, :only_mounted}
    end

    test "rejects mounting where prohibited and while swimming", %{character: character} do
      spell = %{mount(1, 2404, 60) | aura_interrupt_flags: 0x80}
      assert Mount.validate(character, spell, []) == :ok

      assert Mount.validate(character, spell, mount_context: %Mount.Context{mount_allowed?: false}) ==
               {:error, :no_mounts_allowed}

      swimming = %{character | movement_block: %{character.movement_block | movement_flags: 0x00200000}}
      assert Mount.validate(swimming, spell, []) == {:error, :only_abovewater}
    end

    test "rejects casts during taxi flights", %{character: character} do
      flight = %Flight{
        token: make_ref(),
        path_ids: [1],
        source_node_id: 1,
        destination_node_id: 2,
        destination_position: {10.0, 0.0, 0.0},
        mount_display_id: 6852,
        started_at: 1000,
        duration_ms: 5000
      }

      character = %{character | internal: %{character.internal | taxi_flight: flight}}
      assert Mount.validate(character, mount(1, 2404, 60), []) == {:error, :not_on_taxi}
    end
  end

  describe "resolve_requirements/4" do
    test "mount admission is rechecked at launch before power or cooldowns are spent", %{character: c} do
      spell = qiraji()
      casting = Cast.new(spell, Target.self(1), 1_000)
      c = %{c | internal: %{c.internal | casting: casting}}
      requirements = %Requirements{mount_context: %Mount.Context{mount_allowed?: false}}
      failed = Casting.resolve_requirements(c, casting, requirements, 2_000)
      assert failed.internal.casting == nil
      assert failed.internal.cooldowns == %{}
      assert Enum.any?(failed.internal.events, &match?(%Effects.SpellCastFailed{reason: :no_mounts_allowed}, &1))
    end

    test "a mount acquired during the cast turns Black Qiraji completion into a dismount", %{character: c} do
      {mounted, _} = apply_spell(c, mount(1, 2404, 100))
      casting = Cast.new(qiraji(), Target.self(1), 1_000)
      mounted = %{mounted | internal: %{mounted.internal | casting: casting}}
      failed = Casting.resolve_requirements(mounted, casting, %Requirements{mount_context: %Mount.Context{}}, 2_000)
      assert failed.unit.mount_display_id == 0
      assert failed.movement_block.run_speed == 7.0
      assert failed.internal.casting == nil
      assert failed.internal.cooldowns == %{}
    end
  end

  defp character(_context) do
    character = %Character{
      object: %Object{guid: 1},
      unit: %Unit{health: 100, max_health: 100, level: 60, auras: [], display_id: 49, native_display_id: 49},
      player: %Player{},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: struct!(%MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}, MovementBlock.player_speeds())
    }

    %{character: character}
  end

  defp apply_spell(character, spell), do: Aura.apply_spell(character, 1, 60, spell, 1000)

  defp mount(id, display, speed) do
    %Spell{
      id: id,
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :mounted, misc_value: display},
        %Effect{index: 1, type: :apply_aura, aura: :mod_increase_mounted_speed, base_points: speed}
      ]
    }
  end

  defp buff(id, type, amount) do
    %Spell{id: id, effects: [%Effect{index: 0, type: :apply_aura, aura: type, base_points: amount}]}
  end

  defp holly do
    %Spell{
      id: 25_860,
      attributes: MapSet.new([:allow_while_mounted]),
      effects: [%Effect{index: 0, type: :dummy, implicit_target_a: :caster}]
    }
  end

  defp qiraji do
    %Spell{
      id: 26_656,
      attributes: MapSet.new([:allow_while_mounted]),
      effects: [%Effect{index: 0, type: :script_effect, implicit_target_a: :caster}]
    }
  end

  defp discombobulate do
    %Spell{
      id: 4060,
      duration_ms: 5_000,
      attributes: MapSet.new([:negative]),
      effects: [
        %Effect{index: 0, type: :apply_aura, aura: :transform, appearance: %Model{display_id: 100}},
        %Effect{index: 1, type: :apply_aura, aura: :mod_decrease_speed, base_points: -20}
      ]
    }
  end
end
