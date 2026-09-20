defmodule ThistleTea.Game.World.SpellMagnets do
  @moduledoc """
  Serializes spell-magnet charge claims across protected party members.
  Entity owners publish aura transitions; process monitors retire departed
  sources and recipients. Claims never call an entity process.
  """

  use GenServer

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Entity
  alias ThistleTea.Game.Entity.Logic.Hostility
  alias ThistleTea.Game.Entity.Logic.SpellMagnet
  alias ThistleTea.Game.Spell
  alias ThistleTea.Game.Time
  alias ThistleTea.Game.World
  alias ThistleTea.Game.World.Metadata

  require Logger

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, %{}, Keyword.put_new(opts, :name, __MODULE__))

  def sync(guid, owner, magnets, server \\ __MODULE__) when is_pid(owner) do
    GenServer.call(server, {:sync, guid, owner, magnets})
  end

  def redirect(caster, %Spell{} = spell, target_guid, server \\ __MODULE__) do
    if SpellMagnet.eligible?(spell) do
      GenServer.call(server, {:redirect, caster, spell, target_guid, Time.now()})
    else
      target_guid
    end
  end

  @impl GenServer
  def init(_opts), do: {:ok, %{entities: %{}, monitors: %{}}}

  @impl GenServer
  def handle_call({:sync, guid, owner, magnets}, _from, state) do
    previous =
      case Map.get(state.entities, guid) do
        %{owner: ^owner, magnets: previous} -> previous
        _ -> []
      end

    magnets = Enum.map(magnets, &retain_charges(&1, previous, guid))
    state = monitor_owner(state, guid, owner)
    entities = Map.put(state.entities, guid, %{magnets: magnets, owner: owner})
    {:reply, :ok, %{state | entities: entities}}
  rescue
    error ->
      Logger.error("Spell-magnet publication failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, {:error, error}, state}
  end

  def handle_call({:redirect, caster, spell, target_guid, now}, _from, state) do
    recipient = Map.get(state.entities, target_guid, %{magnets: []})

    magnet =
      Enum.find_value(recipient.magnets, fn protection ->
        source = source_magnet(state, protection)

        if is_map(source) and active?(protection, now) and active?(source, now) and
             valid_target?(caster, spell, target_guid, source) do
          source
        end
      end)

    case magnet do
      nil -> {:reply, target_guid, state}
      magnet -> {:reply, magnet.source_guid, consume(state, magnet)}
    end
  rescue
    error ->
      Logger.error("Spell-magnet redirection failed: #{Exception.format(:error, error, __STACKTRACE__)}")
      {:reply, target_guid, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {guid, monitors} = Map.pop(state.monitors, ref)
    {:noreply, %{state | monitors: monitors, entities: Map.delete(state.entities, guid)}}
  end

  defp retain_charges(magnet, previous, guid) do
    old = Enum.find(previous, &(&1.spell_id == magnet.spell_id and &1.applied_at == magnet.applied_at))
    if magnet.source_guid == guid and old, do: %{magnet | charges: old.charges}, else: magnet
  end

  defp monitor_owner(state, guid, owner) do
    case Map.get(state.entities, guid) do
      %{owner: ^owner} -> state
      _ -> replace_monitor(state, guid, owner)
    end
  end

  defp replace_monitor(state, guid, owner) do
    monitors =
      Map.reject(state.monitors, fn {ref, monitored} ->
        if monitored == guid do
          Process.demonitor(ref, [:flush])
          true
        else
          false
        end
      end)

    %{state | monitors: Map.put(monitors, Process.monitor(owner), guid)}
  end

  defp source_magnet(state, protection) do
    case Map.get(state.entities, protection.source_guid) do
      %{magnets: magnets, owner: owner} ->
        if Process.alive?(owner),
          do: Enum.find(magnets, &(&1.source_guid == protection.source_guid and &1.spell_id == protection.spell_id))

      _ ->
        nil
    end
  end

  defp active?(%{charges: 0}, _now), do: false
  defp active?(%{expires_at: expires}, now) when is_integer(expires) and expires != -1, do: now < expires
  defp active?(_magnet, _now), do: true

  defp valid_target?(caster, spell, target_guid, magnet) do
    guid = magnet.source_guid

    with %{alive?: true} = metadata <- Metadata.get(guid),
         true <- ((Map.get(metadata, :unit_flags) || 0) &&& 0x02010002) == 0,
         true <- creature_type_allowed?(spell, metadata),
         true <- Hostility.valid_attack_target?(caster, target_guid),
         {world, _, _, _} <- World.position(caster),
         {^world, x, y, z} <- World.position(guid),
         {^world, tx, ty, tz} <- World.position(target_guid) do
      not is_number(magnet.radius) or
        (x - tx) * (x - tx) + (y - ty) * (y - ty) + (z - tz) * (z - tz) <= magnet.radius * magnet.radius
    else
      _ -> false
    end
  end

  defp creature_type_allowed?(spell, metadata) do
    Enum.any?(Map.get(metadata, :aura_sources, []), fn {id, _, _, _, _} -> id == 8179 end) or
      Spell.creature_type_mask_ignored?(spell) or Spell.creature_type_allowed?(spell, Map.get(metadata, :creature_type))
  end

  defp consume(state, %{charges: charges} = magnet) when is_integer(charges) and charges > 0 do
    source = Map.fetch!(state.entities, magnet.source_guid)
    updated = %{magnet | charges: charges - 1}
    magnets = Enum.map(source.magnets, fn entry -> if entry == magnet, do: updated, else: entry end)
    state = %{state | entities: Map.put(state.entities, magnet.source_guid, %{source | magnets: magnets})}

    if updated.charges == 0, do: remove_protection(state.entities, magnet)

    state
  end

  defp consume(state, _magnet), do: state

  defp remove_protection(entities, magnet) do
    Enum.each(entities, fn {guid, entity} ->
      if Enum.any?(entity.magnets, &(&1.source_guid == magnet.source_guid and &1.spell_id == magnet.spell_id)) do
        Entity.remove_aura(guid, magnet.spell_id, magnet.source_guid)
      end
    end)
  end
end
