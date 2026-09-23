defmodule ThistleTea.Game.Player.Instances do
  @moduledoc "Instance admission, membership grace periods, and safe recovery to the player's home bind."

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Data.Character
  alias ThistleTea.Game.Entity.Data.HomeBind
  alias ThistleTea.Game.Entity.Server.Player.State
  alias ThistleTea.Game.Instance.Eviction
  alias ThistleTea.Game.Network
  alias ThistleTea.Game.Network.Message
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World.Loader.MapTemplate
  alias ThistleTea.Game.World.System.Battleground, as: BattlegroundSystem
  alias ThistleTea.Game.World.System.Instance, as: InstanceSystem
  alias ThistleTea.Game.WorldRef

  def reject(:raid_group_required), do: Network.send_packet(%Message.SmsgRaidGroupOnly{})
  def reject(reason), do: Network.send_packet(%Message.SmsgTransferAborted{reason: reason})

  def send_raid_info(guid) do
    Network.send_packet(%Message.SmsgRaidInstanceInfo{raids: InstanceSystem.saved_raids(guid)})
  end

  def send_saved_instances(guid) do
    raids = InstanceSystem.saved_raids(guid)
    Network.send_packet(%Message.SmsgUpdateInstanceOwnership{player_is_saved_to_a_raid: raids != []})
    Enum.each(raids, &Network.send_packet(%Message.SmsgUpdateLastInstance{map: &1.map_id}))
  end

  def lockout_changed(guid, reason) do
    if reason == :created, do: Network.send_packet(%Message.SmsgInstanceSaveCreated{})
    send_saved_instances(guid)
    send_raid_info(guid)
  end

  def restore(character, guid, opts \\ [])

  def restore(%Character{internal: %{world: %WorldRef{instance_id: id} = world}} = character, guid, opts)
      when is_integer(id) do
    resume =
      if MapTemplate.battleground?(world.map_id),
        do: Keyword.get(opts, :resume_battleground, &resume_battleground/2),
        else: Keyword.get(opts, :resume, &InstanceSystem.resume/2)

    case resume.(world, guid) do
      {:ok, world} -> %{character | internal: %{character.internal | world: world}}
      {:error, _reason} -> return_home(character)
    end
  end

  def restore(%Character{} = character, _guid, _opts), do: character

  defp resume_battleground(world, guid) do
    case BattlegroundSystem.reconnect(guid, world) do
      :ok -> {:ok, world}
      {:error, _reason} = error -> error
    end
  end

  def refresh(state, opts \\ [])

  def refresh(%State{ready: true, character: %Character{internal: %{world: world}}} = state, opts) do
    valid? = valid_member?(state, opts)
    previous = if state.instance_eviction, do: state.instance_eviction.countdown
    current = Eviction.refresh(previous, world, valid?, now(opts))

    cond do
      current == previous -> state
      is_nil(current) -> clear(state)
      true -> start(clear(state), current)
    end
  end

  def refresh(%State{} = state, _opts), do: state

  def expire(state, token, opts \\ [])

  def expire(
        %State{instance_eviction: %{token: token, countdown: countdown}, character: %Character{} = character} = state,
        token,
        opts
      ) do
    cond do
      character.internal.world != countdown.world ->
        clear(state)

      valid_member?(state, opts) ->
        clear(state)

      Eviction.due?(countdown, character.internal.world, now(opts)) ->
        home = character.internal.home_bind
        {x, y, z} = home.position
        Entity.teleport(self(), WorldRef.open(home.map_id), {x, y, z, 0.0})
        clear(state)

      true ->
        state
    end
  end

  def expire(%State{} = state, _token, _opts), do: state

  def clear(%State{instance_eviction: %{ref: ref}} = state) do
    Process.cancel_timer(ref)
    Network.send_packet(%Message.SmsgRaidGroupOnly{delay_ms: 0})
    %{state | instance_eviction: nil}
  end

  def clear(%State{} = state), do: state

  defp start(state, %Eviction{} = countdown) do
    token = make_ref()
    ref = Process.send_after(self(), {:instance_eviction, token}, Eviction.delay_ms())
    Network.send_packet(%Message.SmsgRaidGroupOnly{delay_ms: Eviction.delay_ms()})
    %{state | instance_eviction: %{ref: ref, token: token, countdown: countdown}}
  end

  defp valid_member?(%State{character: %Character{internal: %{world: %WorldRef{instance_id: nil}}}}, _opts), do: true

  defp valid_member?(%State{guid: guid, character: %Character{internal: %{world: world}}}, opts) do
    valid? = Keyword.get(opts, :valid?, &InstanceSystem.valid_member?/2)
    not MapTemplate.dungeon?(world.map_id) or valid?.(world, guid)
  end

  defp now(opts), do: Keyword.get_lazy(opts, :now, &Time.now/0)

  defp return_home(%Character{internal: %{home_bind: %HomeBind{} = home}} = character) do
    {x, y, z} = home.position
    internal = %{character.internal | world: WorldRef.open(home.map_id), area: home.area_id}
    movement = %{character.movement_block | position: {x, y, z, 0.0}}
    %{character | internal: internal, movement_block: movement}
  end
end
