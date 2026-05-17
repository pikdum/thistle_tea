defmodule ThistleTea.Game.World.Loader.Faction do
  @moduledoc false

  alias ThistleTea.DBC

  def metadata(faction_template_id) when is_integer(faction_template_id) and faction_template_id > 0 do
    %{
      faction_template_id: faction_template_id,
      faction_template: DBC.get(FactionTemplate, faction_template_id)
    }
  end

  def metadata(_faction_template_id) do
    %{
      faction_template_id: nil,
      faction_template: nil
    }
  end
end
