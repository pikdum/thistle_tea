defmodule ThistleTea.Game.Entity.Data.GameObjectTemplate do
  @moduledoc false
  alias ThistleTea.DB.Mangos

  defstruct [:entry, :type, :display_id, :name, data: []]

  def build(%Mangos.GameObjectTemplate{} = template) do
    %__MODULE__{
      entry: template.entry,
      type: template.type,
      display_id: template.display_id,
      name: template.name,
      data:
        Enum.map(0..23, fn index ->
          Map.get(template, :"data#{index}") || 0
        end)
    }
  end
end
