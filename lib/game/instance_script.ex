defmodule ThistleTea.Game.InstanceScript do
  @moduledoc """
  Registry for audited instance-script data adapters.
  """

  alias ThistleTea.Game.InstanceScript.Stratholme

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

  def set_data(script_name, field, value) do
    with adapter when not is_nil(adapter) <- adapter(script_name),
         true <- field in adapter.registered_fields() do
      adapter.set_data(field, value)
    else
      nil -> {:error, {:unsupported_script, script_name}}
      false -> {:error, {:unsupported_field, field}}
    end
  end

  defp adapter("instance_stratholme"), do: Stratholme
  defp adapter(_script_name), do: nil
end

defmodule ThistleTea.Game.InstanceScript.Stratholme do
  @moduledoc false

  @aurius_event 7

  def registered_fields, do: [@aurius_event]
  def initial_value(@aurius_event), do: 0
  def set_data(@aurius_event, value), do: {:ok, value, []}
end
