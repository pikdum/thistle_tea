defmodule ThistleTea.Game.Core.InstanceScript do
  @moduledoc """
  Registry for audited instance-script data adapters.
  """

  alias ThistleTea.Game.Core.InstanceScript.BlackfathomDeeps
  alias ThistleTea.Game.Core.InstanceScript.BlackrockDepths
  alias ThistleTea.Game.Core.InstanceScript.Deadmines
  alias ThistleTea.Game.Core.InstanceScript.RazorfenKraul
  alias ThistleTea.Game.Core.InstanceScript.RuinsOfAhnQiraj
  alias ThistleTea.Game.Core.InstanceScript.ScarletMonastery
  alias ThistleTea.Game.Core.InstanceScript.ShadowfangKeep
  alias ThistleTea.Game.Core.InstanceScript.Stratholme
  alias ThistleTea.Game.Core.InstanceScript.SunkenTemple

  @adapters [
    BlackfathomDeeps,
    BlackrockDepths,
    Deadmines,
    RazorfenKraul,
    RuinsOfAhnQiraj,
    ScarletMonastery,
    ShadowfangKeep,
    Stratholme,
    SunkenTemple
  ]

  def broadcast_text_ids do
    @adapters |> Enum.flat_map(& &1.broadcast_text_ids()) |> Enum.uniq()
  end

  def summon_entries do
    @adapters |> Enum.flat_map(& &1.summon_entries()) |> Enum.uniq()
  end

  def game_object_db_guids do
    @adapters |> Enum.flat_map(& &1.game_object_db_guids()) |> Enum.uniq()
  end

  def scripted_door?(script_name, entry) do
    case adapter(script_name) do
      nil -> false
      adapter -> entry in adapter.door_entries()
    end
  end

  def data64(script_name, index) do
    case adapter(script_name) do
      nil -> nil
      adapter -> adapter.data64(index)
    end
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

  def game_object_used(script_name, data, script_state, entry) do
    case adapter(script_name) do
      nil -> {:error, {:unsupported_script, script_name}}
      adapter -> adapter.game_object_used(data, script_state, entry)
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

  defp adapter("instance_blackfathom_deeps"), do: BlackfathomDeeps
  defp adapter("instance_blackrock_depths"), do: BlackrockDepths
  defp adapter("instance_deadmines"), do: Deadmines
  defp adapter("instance_razorfen_kraul"), do: RazorfenKraul
  defp adapter("instance_ruins_of_ahnqiraj"), do: RuinsOfAhnQiraj
  defp adapter("instance_scarlet_monastery"), do: ScarletMonastery
  defp adapter("instance_shadowfang_keep"), do: ShadowfangKeep
  defp adapter("instance_stratholme"), do: Stratholme
  defp adapter("instance_sunken_temple"), do: SunkenTemple
  defp adapter(_script_name), do: nil
end
