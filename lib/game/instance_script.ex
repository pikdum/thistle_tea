defmodule ThistleTea.Game.InstanceScript do
  @moduledoc """
  Registry for audited instance-script data adapters.
  """

  alias ThistleTea.Game.InstanceScript.Deadmines
  alias ThistleTea.Game.InstanceScript.Stratholme

  @adapters [Deadmines, Stratholme]

  def broadcast_text_ids do
    @adapters |> Enum.flat_map(& &1.broadcast_text_ids()) |> Enum.uniq()
  end

  def summon_entries do
    @adapters |> Enum.flat_map(& &1.summon_entries()) |> Enum.uniq()
  end

  def registered_fields(script_name) do
    case adapter(script_name) do
      nil -> []
      adapter -> adapter.registered_fields()
    end
  end

  def initial_value(script_name, field) do
    with adapter when not is_nil(adapter) <- adapter(script_name),
         true <- field in adapter.registered_fields() do
      {:ok, adapter.initial_value(field)}
    else
      nil -> {:error, {:unsupported_script, script_name}}
      false -> {:error, {:unsupported_field, field}}
    end
  end

  def set_data(script_name, data, field, value) do
    with adapter when not is_nil(adapter) <- adapter(script_name),
         true <- field in adapter.registered_fields() do
      adapter.set_data(data, field, value)
    else
      nil -> {:error, {:unsupported_script, script_name}}
      false -> {:error, {:unsupported_field, field}}
    end
  end

  def game_object_used(script_name, data, entry) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.game_object_used(data, entry)
    end
  end

  def game_object_spawned(script_name, data, script_state, entry) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.game_object_spawned(data, script_state, entry)
    end
  end

  def creature_event(script_name, data, script_state, event) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.creature_event(data, script_state, event)
    end
  end

  def timer(script_name, data, script_state, key) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.timer(data, script_state, key)
    end
  end

  defp adapter("instance_deadmines"), do: Deadmines
  defp adapter("instance_stratholme"), do: Stratholme
  defp adapter(_script_name), do: nil
end
