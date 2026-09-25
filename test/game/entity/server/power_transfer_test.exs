defmodule ThistleTea.Game.Entity.Server.PowerTransferTest do
  use ExUnit.Case, async: false

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.MovementBlock
  alias ThistleTea.Game.Entity.Data.Component.Object
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.EventSink.Context
  alias ThistleTea.Game.Entity.Logic.Effects
  alias ThistleTea.Game.Entity.Server.Mob, as: MobServer
  alias ThistleTea.Game.Entity.Server.Player, as: PlayerServer
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.SpatialHash
  alias ThistleTea.Game.WorldRef

  describe "handle_cast/2" do
    test "periodic leech threat goes to the drained creature without splitting among attackers" do
      caster = entity(:player)
      mob = entity(:mob)
      caster_guid = caster.object.guid
      mob = %{mob | internal: %{mob.internal | in_combat: true, threat: %{caster_guid => 1.0}}}

      Metadata.put(caster_guid, %{
        alive?: true,
        faction_template: %FactionTemplate{id: 1, faction: 1, faction_group: 1, enemy_group: 8},
        attackers: MapSet.new([mob.object.guid, 123])
      })

      Metadata.put(mob.object.guid, %{
        faction_template: %FactionTemplate{id: 17, faction: 15, faction_group: 8, enemy_group: 1}
      })

      on_exit(fn ->
        Metadata.delete(caster_guid)
        Metadata.delete(mob.object.guid)
      end)

      effect = %Effects.AddThreat{source_guid: caster_guid, target_guid: mob.object.guid, amount: 10.0}
      assert {:noreply, updated} = MobServer.handle_cast({:add_threat, effect}, mob)
      assert updated.internal.threat[caster_guid] == 11.0
      assert is_reference(updated.internal.ai_tick_ref)
      Process.cancel_timer(updated.internal.ai_tick_ref)
      Metadata.update(caster_guid, %{alive?: false})
      assert MobServer.handle_cast({:add_threat, effect}, mob) == {:noreply, mob}
    end

    test "player and creature owners receive grants and leeches", _context do
      for kind <- [:player, :mob] do
        entity = entity(kind)
        guid = entity.object.guid
        Entity.register(guid)
        on_exit(fn -> Entity.unregister(guid) end)
        server = if kind == :player, do: PlayerServer, else: MobServer
        state = if kind == :player, do: %State{character: entity}, else: entity

        grant = %Effects.GrantPower{
          source_guid: 99,
          target_guid: guid,
          misc_value: 0,
          amount: 30,
          spell: %Spell{id: 123}
        }

        EventSink.emit(%Mob{object: %Object{guid: 99}}, grant)
        assert_receive {:"$gen_cast", {:grant_power, ^grant} = command}
        assert {:noreply, state, {:continue, _}} = server.handle_cast(command, state)
        updated = if kind == :player, do: state.character, else: state
        assert updated.unit.power1 == 40

        leech = %Effects.LeechPower{
          source_guid: guid,
          target_guid: 99,
          spell: %Spell{id: 18_220},
          power_type: 0,
          amount: 150,
          multiplier: 1.0
        }

        EventSink.emit(%Mob{object: %Object{guid: 99}}, leech)
        assert_receive {:"$gen_cast", {:leech_power, ^leech} = command}
        assert {:noreply, state, {:continue, _}} = server.handle_cast(command, state)
        updated = if kind == :player, do: state.character, else: state
        assert updated.unit.power1 == 100

        dead = %{updated | unit: %{updated.unit | health: 0, power1: 0}}
        state = if kind == :player, do: %{state | character: dead}, else: dead
        assert {:noreply, state, {:continue, _}} = server.handle_cast(command, state)
        updated = if kind == :player, do: state.character, else: state
        assert updated.unit.power1 == 0
      end
    end
  end

  describe "emit/3" do
    test "local transfers use the explicit owner for either entity type" do
      for kind <- [:player, :mob] do
        entity = entity(kind)
        grant = %Effects.GrantPower{target_guid: entity.object.guid, misc_value: 0, amount: 10}

        leech = %Effects.LeechPower{
          source_guid: entity.object.guid,
          target_guid: 99,
          spell: %Spell{id: 5138},
          power_type: 0,
          amount: 10,
          multiplier: 1.0
        }

        for {effect, name} <- [{grant, :grant_power}, {leech, :leech_power}] do
          EventSink.emit(entity, effect)
          refute_received {:"$gen_cast", {^name, ^effect}}
          EventSink.emit(entity, effect, Context.new(self()))
          assert_received {:"$gen_cast", {^name, ^effect}}
        end
      end
    end

    test "resource combat logs reach the owner and observers only in the same world" do
      character = entity(:player)
      owner = character.object.guid
      observer = entity(:player).object.guid
      remote = entity(:player).object.guid

      for {guid, world} <- [{owner, 0}, {observer, 0}, {remote, 1}] do
        Entity.register(guid)
        SpatialHash.update(:players, guid, world, 0.0, 0.0, 0.0)
      end

      on_exit(fn ->
        for guid <- [owner, observer, remote] do
          Entity.unregister(guid)
          SpatialHash.remove(:players, guid)
        end
      end)

      effects = [
        {%Effects.SpellEnergize{source_guid: owner, target_guid: owner, spell_id: 123, power_type: 0, amount: 50},
         %Message.SmsgSpellenergizelog{caster: owner, target: owner, spell_id: 123, power_type: 0, amount: 50}},
        {%Effects.SpellPowerDrain{
           source_guid: owner,
           target_guid: 99,
           spell_id: 18_220,
           power_type: 0,
           amount: 50,
           multiplier: 0.5
         }, %Message.SmsgSpelllogexecute{caster: owner, spell_id: 18_220, logs: [{:power_drain, 99, 50, 0, 0.5}]}},
        {%Effects.PeriodicAuraLog{
           source_guid: owner,
           target_guid: 99,
           spell_id: 5138,
           aura_type: :periodic_mana_leech,
           amount: 50,
           misc_value: 0,
           multiplier: 0.5
         },
         %Message.SmsgPeriodicauralog{
           caster: owner,
           target: 99,
           spell_id: 5138,
           auras: [%{aura_type: :periodic_mana_leech, amount: 50, misc_value: 0, multiplier: 0.5}]
         }}
      ]

      for {effect, packet} <- effects do
        EventSink.emit(character, effect)
        assert_receive {:"$gen_cast", {:send_packet, ^packet}}
        assert_receive {:"$gen_cast", {:send_packet, ^packet, _opts}}
        refute_received {:"$gen_cast", {:send_packet, ^packet}}
        refute_received {:"$gen_cast", {:send_packet, ^packet, _opts}}
      end
    end

    test "direct leech threat routes only to creatures" do
      for kind <- [:player, :mob] do
        target = entity(kind)
        Entity.register(target.object.guid)
        on_exit(fn -> Entity.unregister(target.object.guid) end)
        effect = %Effects.AddThreat{source_guid: 99, target_guid: target.object.guid, amount: 10.0}
        EventSink.emit(entity(:player), effect)

        if kind == :mob do
          assert_receive {:"$gen_cast", {:add_threat, ^effect}}
          assert MobServer.handle_cast({:add_threat, effect}, target) == {:noreply, target}
        else
          refute_received {:"$gen_cast", {:add_threat, ^effect}}
        end
      end
    end
  end

  defp entity(kind) do
    low = System.unique_integer([:positive, :monotonic])
    guid = if kind == :player, do: Guid.from_low_guid(:player, low), else: Guid.from_low_guid(:mob, 1, low)
    module = if kind == :player, do: Character, else: Mob

    struct!(module,
      object: %Object{guid: guid},
      unit: %Unit{health: 100, max_health: 100, power_type: 0, power1: 10, max_power1: 100, auras: []},
      internal: %Internal{world: WorldRef.open(0)},
      movement_block: %MovementBlock{position: {0.0, 0.0, 0.0, 0.0}}
    )
  end
end
