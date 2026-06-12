defmodule ThistleTea.Game.Entity.Server.Mob do
  @moduledoc """
  Owning GenServer for a mob: ticks its behavior tree and applies incoming
  attacks and spells through the pure core. The post-death lifecycle is
  delegated — the corpse phase (loot, rolls, decay, removal) to `Mob.Corpse`
  and the respawn state machine to `Mob.Respawn`.
  """
  use GenServer

  import Bitwise, only: [|||: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Component.Internal
  alias ThistleTea.Game.Entity.Data.Component.Internal.Loot
  alias ThistleTea.Game.Entity.Data.Component.Unit
  alias ThistleTea.Game.Entity.Data.Mob
  alias ThistleTea.Game.Entity.EventSink
  alias ThistleTea.Game.Entity.Logic.AI.BT
  alias ThistleTea.Game.Entity.Logic.AI.BT.Mob, as: MobBT
  alias ThistleTea.Game.Entity.Logic.AI.Tick
  alias ThistleTea.Game.Entity.Logic.Combat
  alias ThistleTea.Game.Entity.Logic.Core
  alias ThistleTea.Game.Entity.Logic.Experience
  alias ThistleTea.Game.Entity.Logic.Movement
  alias ThistleTea.Game.Entity.Logic.SpellEffect
  alias ThistleTea.Game.Entity.Registry, as: EntityRegistry
  alias ThistleTea.Game.Entity.Server.Mob.Corpse
  alias ThistleTea.Game.Entity.Server.Mob.Respawn
  alias ThistleTea.Game.Guid
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Party
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata
  alias ThistleTea.Game.World.System.GameEvent
  alias ThistleTea.Game.World.System.Party, as: PartySystem
  alias ThistleTea.Game.World.Visibility

  require Logger

  @ai_tick_retry_ms 1_000
  @dynamic_flag_tapped 0x0004

  def start_link(%Mob{} = state) do
    GenServer.start_link(__MODULE__, state, name: EntityRegistry.via(state.object.guid))
  end

  @impl GenServer
  def init(%Mob{} = state) do
    GameEvent.subscribe(state)
    Process.flag(:trap_exit, true)
    state = BT.init(state, MobBT.tree())
    World.update_position(state)
    state = Visibility.join_entity(state)

    schedule_ai_tick(0)

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:send_update_to, pid}, state) do
    if Corpse.removed?(state) do
      {:noreply, state}
    else
      state = Movement.sync_position(state, Time.now())
      World.update_position(state)
      state = Visibility.refresh_entity(state)

      Core.update_object(state)
      |> Network.send_packet(pid)

      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_cast({:move_to, x, y, z}, state) do
    state = Movement.move_to(state, {x, y, z}, [], Time.now())
    state = EventSink.emit_pending(state)
    {:noreply, state}
  end

  @impl GenServer
  def handle_cast({:receive_spell, caster, spell}, state) do
    caster_guid = caster_guid(caster)

    state =
      if Spell.harmful?(spell) do
        state
        |> maybe_reset_attack_started(caster_guid)
        |> engage_combat(caster_guid)
      else
        state
      end

    target = state.unit.target
    dead_before = Core.dead?(state)

    {state, events} = SpellEffect.receive(state, caster, spell, Time.now())

    state =
      state
      |> EventSink.emit(events)
      |> handle_death_transition(target, dead_before)

    schedule_ai_tick(0)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_cast({:receive_heal, amount}, state) do
    state = Core.heal(state, amount)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_cast({:loot_roll_vote, voter_guid, slot, vote}, %Mob{} = state) do
    {:noreply, Corpse.roll_vote(state, voter_guid, slot, vote)}
  end

  @impl GenServer
  def handle_cast({:receive_attack, %{caster: caster} = attack}, state) do
    state =
      state
      |> maybe_reset_attack_started(caster)
      |> engage_combat(caster)

    target = state.unit.target
    dead_before = Core.dead?(state)

    {state, events} = Combat.receive_attack(state, attack, Time.now())

    state =
      state
      |> handle_death_transition(target, dead_before)
      |> EventSink.emit(events)

    schedule_ai_tick(0)
    {:noreply, state, {:continue, :maybe_broadcast}}
  end

  @impl GenServer
  def handle_call({:loot_view, viewer}, _from, %Mob{} = state) do
    {result, state} = Corpse.view(state, viewer)
    {:reply, result, state}
  end

  def handle_call({:loot_master_give, giver, slot, target}, _from, %Mob{} = state) do
    {result, state} = Corpse.master_give(state, giver, slot, target)
    {:reply, result, state}
  end

  def handle_call({:loot_take_item, slot}, _from, %Mob{} = state) do
    {result, state} = Corpse.take_item(state, slot)
    {:reply, result, state}
  end

  def handle_call({:loot_return_item, slot}, _from, %Mob{} = state) do
    {:reply, :ok, Corpse.return_item(state, slot)}
  end

  def handle_call(:loot_take_gold, _from, %Mob{} = state) do
    {result, state} = Corpse.take_gold(state)
    {:reply, result, state}
  end

  def handle_call({:loot_release, viewer}, _from, %Mob{} = state) do
    {:reply, :ok, Corpse.release(state, viewer)}
  end

  @impl GenServer
  def handle_info({:loot_roll_timeout, slot}, %Mob{} = state) do
    {:noreply, Corpse.roll_timeout(state, slot)}
  end

  @impl GenServer
  def handle_info({:remove_corpse, token}, %Mob{} = state) do
    {:noreply, Corpse.remove(state, token)}
  end

  @impl GenServer
  def handle_info({:deliver_spell, event}, state) do
    EventSink.deliver_spell(event)
    {:noreply, state}
  rescue
    error ->
      Logger.error("deliver_spell crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:noreply, state}
  end

  @impl GenServer
  def handle_info(:ai_tick, %{internal: %Internal{behavior_tree: behavior_tree}} = state) do
    if Corpse.removed?(state) do
      {:noreply, state}
    else
      state = Movement.sync_position(state, Time.now())
      World.update_position(state)
      state = Visibility.refresh_entity(state)
      {status, state} = BT.tick(behavior_tree, state)
      state = EventSink.emit_pending(state)
      schedule_ai_tick(Tick.mob_delay(status))
      {:noreply, state, {:continue, :maybe_broadcast}}
    end
  rescue
    error ->
      Logger.error("Mob AI tick crashed: #{Exception.format(:error, error, __STACKTRACE__)}")
      schedule_ai_tick(@ai_tick_retry_ms)
      {:noreply, state}
  end

  def handle_info(:respawn, %Mob{} = state) do
    {:noreply, Respawn.handle(state)}
  end

  def handle_info({:event_stop, _event}, state) do
    pid = self()

    Task.start(fn ->
      World.stop_entity(pid)
    end)

    {:noreply, state}
  end

  def handle_info({:event_start, _event}, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_continue(:maybe_broadcast, %{internal: %Internal{broadcast_update?: true}} = state) do
    if !Corpse.removed?(state) do
      update_type = if Core.dead?(state), do: :create_object2, else: :values
      Core.update_object(state, update_type) |> World.broadcast_packet(state)
      Metadata.update(state.object.guid, %{alive?: not Core.dead?(state)})
    end

    internal = %{state.internal | broadcast_update?: false}
    {:noreply, %{state | internal: internal}}
  end

  def handle_continue(:maybe_broadcast, state) do
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    World.remove_position(state)
    Visibility.leave_entity(state)
    Metadata.delete(state.object.guid)
  end

  defp schedule_ai_tick(delay) when is_integer(delay) and delay >= 0 do
    Process.send_after(self(), :ai_tick, delay)
  end

  defp engage_combat(%Mob{unit: %Unit{target: current_target} = unit, internal: internal} = state, caster)
       when is_integer(caster) do
    now = Time.now()

    state = update_attacker_count(state, current_target, caster)

    %{
      state
      | unit: %{unit | target: caster},
        internal: %{internal | in_combat: true, last_hostile_time: now}
    }
    |> maybe_tap(caster)
  end

  defp engage_combat(%Mob{} = state, _caster) do
    state
  end

  defp maybe_tap(
         %Mob{unit: %Unit{} = unit, internal: %Internal{loot: %Loot{tapped_by: nil} = loot} = internal} = state,
         caster
       ) do
    if not Core.dead?(state) and Guid.entity_type(caster) == :player do
      group_id =
        case PartySystem.group_of(caster) do
          %Party.Group{id: id} -> id
          _ -> nil
        end

      internal = %{internal | loot: %{loot | tapped_by: %{player: caster, group_id: group_id}}}
      unit = %{unit | dynamic_flags: (unit.dynamic_flags || 0) ||| @dynamic_flag_tapped}
      Metadata.update(state.object.guid, %{tapped_player: caster, tapped_group_id: group_id})

      %{state | unit: unit, internal: internal}
      |> Core.mark_broadcast_update()
    else
      state
    end
  end

  defp maybe_tap(%Mob{} = state, _caster), do: state

  defp maybe_reset_attack_started(%Mob{unit: %Unit{target: target}} = state, caster) when is_integer(caster) do
    if target == caster do
      state
    else
      BT.reset_attack_started(state)
    end
  end

  defp maybe_reset_attack_started(state, _caster), do: state

  defp update_attacker_count(%Mob{} = state, current_target, caster) do
    if is_integer(current_target) and current_target > 0 and current_target != caster do
      Metadata.decrement(current_target, :attacker_count, 0)
    end

    if is_integer(caster) and caster > 0 and current_target != caster do
      Metadata.increment(caster, :attacker_count)
    end

    state
  end

  defp update_attacker_count(state, _current_target, _caster), do: state

  defp handle_death_transition(%Mob{} = state, target, false) do
    if Core.dead?(state) do
      state
      |> maybe_decrement_on_death(target)
      |> maybe_reward_kill(target)
      |> Corpse.prepare(target)
      |> Respawn.schedule()
    else
      state
    end
  end

  defp handle_death_transition(%Mob{} = state, _target, _dead_before), do: state

  defp maybe_decrement_on_death(%Mob{} = state, target) when is_integer(target) and target > 0 do
    Metadata.decrement(target, :attacker_count, 0)
    state
  end

  defp maybe_decrement_on_death(%Mob{} = state, _target), do: state

  defp maybe_reward_kill(%Mob{} = state, target) when is_integer(target) and target > 0 do
    if Guid.entity_type(target) == :player do
      case PartySystem.group_of(target) do
        %Party.Group{} = group -> reward_group_kill(state, group)
        _ -> Entity.reward_kill(target, state)
      end
    end

    state
  end

  defp maybe_reward_kill(%Mob{} = state, _target), do: state

  defp reward_group_kill(%Mob{internal: %Internal{} = internal, unit: %Unit{} = unit} = state, group) do
    member_guids = MapSet.new(group.members, & &1.guid)

    eligible =
      state
      |> World.nearby_players(Experience.group_reward_distance())
      |> Enum.filter(fn {guid, _distance} -> MapSet.member?(member_guids, guid) end)
      |> Enum.flat_map(fn {guid, _distance} ->
        case Metadata.query(guid, [:level, :alive?]) do
          %{level: level, alive?: true} when is_integer(level) -> [%{guid: guid, level: level}]
          _ -> []
        end
      end)

    opts = [
      experience_multiplier: internal.creature.experience_multiplier,
      extra_flags: internal.creature.extra_flags,
      elite?: Experience.elite_rank?(internal.creature.rank)
    ]

    eligible
    |> Experience.group_shares(unit.level, opts)
    |> Enum.each(fn {guid, xp} -> Entity.reward_kill_share(guid, state, xp) end)
  end

  defp caster_guid(%{caster_guid: caster_guid}) when is_integer(caster_guid), do: caster_guid
  defp caster_guid(caster_guid) when is_integer(caster_guid), do: caster_guid
  defp caster_guid(_caster), do: nil
end
