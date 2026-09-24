defmodule ThistleTea.Game.Entity.Data.CreatureTemplate do
  @moduledoc false
  alias ThistleTea.DB.Mangos

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

  def build(%Mangos.CreatureTemplate{} = ct) do
    %__MODULE__{
      entry: ct.entry,
      name: ct.name,
      sub_name: ct.sub_name,
      type_flags: ct.creature_type_flags,
      creature_type: ct.creature_type,
      family: ct.family,
      rank: ct.rank,
      display_id: ct.model_id1,
      display_ids: [ct.model_id1, ct.model_id2, ct.model_id3, ct.model_id4],
      display_scales: [ct.display_scale1, ct.display_scale2, ct.display_scale3, ct.display_scale4],
      equipment_id: ct.equipment_template_id,
      civilian: ct.civilian,
      racial_leader: ct.racial_leader
    }
  end
end
