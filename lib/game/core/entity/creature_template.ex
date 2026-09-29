defmodule ThistleTea.Game.Core.Entity.CreatureTemplate do
  @moduledoc false
  defstruct [
    :entry,
    :name,
    :sub_name,
    :type_flags,
    :creature_type,
    :family,
    :rank,
    :display_id,
    :display_ids,
    :display_scales,
    :equipment_id,
    :civilian,
    :racial_leader
  ]
end
