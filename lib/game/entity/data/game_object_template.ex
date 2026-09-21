defmodule ThistleTea.Game.Entity.Data.GameObjectTemplate do
  @moduledoc false
  alias ThistleTea.DB.Mangos

  defstruct [:entry, :type, :display_id, :name, :size, :flags, :faction, :bounds, min_gold: 0, max_gold: 0, data: []]

  def lock_id(%__MODULE__{type: type, data: data}) when type in [0, 1], do: Enum.at(data, 1, 0)
  def lock_id(%__MODULE__{type: 25, data: data}), do: Enum.at(data, 4, 0)
  def lock_id(%__MODULE__{type: type, data: data}) when type in [2, 3, 6, 10, 12, 13, 24, 26], do: Enum.at(data, 0, 0)
  def lock_id(_template), do: 0

  def linked_entry(%__MODULE__{type: 1, data: data}), do: Enum.at(data, 3, 0)
  def linked_entry(%__MODULE__{type: 3, data: data}), do: Enum.at(data, 7, 0)
  def linked_entry(%__MODULE__{type: 8, data: data}), do: Enum.at(data, 2, 0)
  def linked_entry(%__MODULE__{type: 10, data: data}), do: Enum.at(data, 12, 0)
  def linked_entry(%__MODULE__{}), do: 0

  def build(%Mangos.GameObjectTemplate{} = template) do
    %__MODULE__{
      entry: template.entry,
      type: template.type,
      display_id: template.display_id,
      name: template.name,
      size: template.size,
      flags: template.flags,
      faction: template.faction,
      min_gold: template.mingold || 0,
      max_gold: template.maxgold || 0,
      data:
        Enum.map(0..23, fn index ->
          Map.get(template, :"data#{index}") || 0
        end)
    }
  end
end
