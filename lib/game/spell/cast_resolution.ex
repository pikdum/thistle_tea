defmodule ThistleTea.Game.Spell.CastResolution do
  @moduledoc """
  Immutable decisions made when a prepared cast launches.

  Target rolls and boundary-facing followups are resolved once, then shared by
  launch, impact, channel ticks, and finish.
  """

  alias __MODULE__.Costs
  alias __MODULE__.Followups
  alias __MODULE__.Impact
  alias __MODULE__.PowerCost

  @enforce_keys [:hits, :misses, :costs, :impacts, :followups]
  defstruct [:hits, :misses, :costs, :impacts, :followups]

  @type t :: %__MODULE__{
          hits: [non_neg_integer()],
          misses: [map()],
          costs: Costs.t(),
          impacts: [Impact.t()],
          followups: Followups.t()
        }

  defmodule Costs do
    @moduledoc false

    @enforce_keys [:power, :channel_power, :reagents, :ammo, :cast_item_guid, :modifier_holder_ids]
    defstruct [:power, :channel_power, :reagents, :ammo, :cast_item_guid, :modifier_holder_ids]

    @type t :: %__MODULE__{
            power: PowerCost.t(),
            channel_power: PowerCost.t(),
            reagents: list(),
            ammo: list(),
            cast_item_guid: non_neg_integer() | nil,
            modifier_holder_ids: [non_neg_integer()]
          }
  end

  defmodule PowerCost do
    @moduledoc false

    @enforce_keys [:power_type, :amount]
    defstruct [:power_type, :amount]

    @type t :: %__MODULE__{power_type: integer() | nil, amount: non_neg_integer()}
  end

  defmodule Impact do
    @moduledoc false

    @enforce_keys [:target_guid, :target_role]
    defstruct [:target_guid, :target_role]

    @type t :: %__MODULE__{
            target_guid: non_neg_integer(),
            target_role: :caster | :pet | :other
          }
  end

  defmodule Followups do
    @moduledoc false

    @enforce_keys [
      :packet_hits,
      :selected_unit_guid,
      :object_guid,
      :item_guid,
      :ground_position,
      :area_position
    ]
    defstruct [:packet_hits, :selected_unit_guid, :object_guid, :item_guid, :ground_position, :area_position]

    @type t :: %__MODULE__{
            packet_hits: [non_neg_integer()],
            selected_unit_guid: non_neg_integer() | nil,
            object_guid: non_neg_integer() | nil,
            item_guid: non_neg_integer() | nil,
            ground_position: {float(), float(), float()} | nil,
            area_position: {float(), float(), float()} | nil
          }
  end
end
