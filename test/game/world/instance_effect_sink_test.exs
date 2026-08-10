defmodule ThistleTea.Game.World.InstanceEffectSinkTest do
  use ExUnit.Case, async: true

  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.InstanceScript.Effects
  alias ThistleTea.Game.World.InstanceEffectSink
  alias ThistleTea.Game.WorldRef

  setup do
    owner = self()
    world = WorldRef.instance(329, 41)
    player = Guid.from_low_guid(:player, 10)
    other_player = Guid.from_low_guid(:player, 11)
    baron = Guid.from_low_guid(:mob, 10_440, 12)
    ysida = Guid.from_low_guid(:mob, 16_031, 13)
    crystal = Guid.from_low_guid(:mob, 10_415, 16)
    door = Guid.from_low_guid(:game_object, 175_405, 14)
    other_door = Guid.from_low_guid(:game_object, 175_796, 15)
    all_guids = [player, other_player, baron, ysida, crystal, door, other_door]

    options = [
      guids: fn ^world -> all_guids end,
      dispatch: fn command -> send(owner, command) end,
      summon: fn summoned_world, entry, position, despawn_delay_ms ->
        send(owner, {:summon, summoned_world, entry, position, despawn_delay_ms})
      end,
      broadcast_text: fn 11_812 -> %{text: "Intruders!", chat_type: :zone_yell} end
    ]

    %{
      world: world,
      player: player,
      other_player: other_player,
      baron: baron,
      ysida: ysida,
      crystal: crystal,
      door: door,
      options: options
    }
  end

  test "targets one loaded game object entry in the exact copy", context do
    effect = %Effects.OperateGameObject{entry: 175_405, action: :close}
    assert :ok = InstanceEffectSink.emit(context.world, effect, context.options)
    assert_receive {:operate_game_object, guid, :close}
    assert guid == context.door
    refute_receive {:operate_game_object, _, _}
  end

  test "fans player effects out to every player in the exact copy", context do
    effect = %Effects.CastPlayerSpell{spell_id: 27_861}
    assert :ok = InstanceEffectSink.emit(context.world, effect, context.options)

    assert_receive {:cast_player_spell, first, 27_861}
    assert_receive {:cast_player_spell, second, 27_861}
    assert MapSet.new([first, second]) == MapSet.new([context.player, context.other_player])
  end

  test "resolves creature entry, broadcast text, movement, and flags", context do
    assert :ok =
             InstanceEffectSink.emit(
               context.world,
               %Effects.MonsterTalk{creature_entry: 10_440, broadcast_text_id: 11_812},
               context.options
             )

    assert_receive {:monster_talk, baron, "Intruders!", :zone_yell}
    assert baron == context.baron

    assert :ok =
             InstanceEffectSink.emit(
               context.world,
               %Effects.ModifyCreatureNpcFlags{creature_entry: 16_031, flags: 3, mode: :add},
               context.options
             )

    assert_receive {:modify_creature_npc_flags, ysida, 3, :add}
    assert ysida == context.ysida

    assert :ok =
             InstanceEffectSink.emit(
               context.world,
               %Effects.ModifyCreatureUnitFlags{creature_entry: 10_440, flags: 0x02000002, mode: :remove},
               context.options
             )

    assert_receive {:modify_creature_unit_flags, baron, 0x02000002, :remove}
    assert baron == context.baron

    assert :ok =
             InstanceEffectSink.emit(
               context.world,
               %Effects.MoveCreature{creature_entry: 16_031, position: {1.0, 2.0, 3.0}},
               context.options
             )

    assert_receive {:move_creature, ^ysida, {1.0, 2.0, 3.0}}
  end

  test "targets one exact creature guid for a script spell", context do
    effect = %Effects.TriggerCreatureSpell{
      creature_entry: 10_415,
      creature_guid: context.crystal,
      spell_id: 5
    }

    assert :ok = InstanceEffectSink.emit(context.world, effect, context.options)
    assert_receive {:trigger_creature_spell, guid, 5}
    assert guid == context.crystal
    refute_receive {:trigger_creature_spell, _, _}
  end

  test "builds summons in the exact copy", context do
    effect = %Effects.SummonCreature{entry: 16_031, position: {1.0, 2.0, 3.0, 4.0}, despawn_delay_ms: 5_000}
    assert :ok = InstanceEffectSink.emit(context.world, effect, context.options)
    assert_receive {:summon, world, 16_031, {1.0, 2.0, 3.0, 4.0}, 5_000}
    assert world == context.world
  end
end
