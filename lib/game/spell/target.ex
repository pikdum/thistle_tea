defmodule ThistleTea.Game.Spell.Target do
  @moduledoc """
  Semantic target selection used by spell logic.

  The primary selection is explicit while source and destination locations may
  accompany it. Network target masks and packed GUIDs belong to `TargetCodec`.
  """

  @type guid :: non_neg_integer()
  @type location :: {float(), float(), float()}
  @type selection ::
          :none
          | {:self, guid()}
          | {:unit, guid()}
          | {:item, guid()}
          | {:object, guid(), :open | :locked}
          | {:corpse, guid(), guid()}

  @enforce_keys [:selection]
  defstruct [:selection, :source_location, :destination_location]

  @type t :: %__MODULE__{
          selection: selection(),
          source_location: location() | nil,
          destination_location: location() | nil
        }

  def none, do: %__MODULE__{selection: :none}

  def self(guid) when is_integer(guid) and guid > 0 do
    %__MODULE__{selection: {:self, guid}}
  end

  def unit(guid) when is_integer(guid) and guid > 0 do
    %__MODULE__{selection: {:unit, guid}}
  end

  def item(guid) when is_integer(guid) and guid > 0 do
    %__MODULE__{selection: {:item, guid}}
  end

  def object(guid, access \\ :open)

  def object(guid, access) when is_integer(guid) and guid > 0 and access in [:open, :locked] do
    %__MODULE__{selection: {:object, guid, access}}
  end

  def corpse(corpse_guid, player_guid)
      when is_integer(corpse_guid) and corpse_guid > 0 and is_integer(player_guid) and player_guid > 0 do
    %__MODULE__{selection: {:corpse, corpse_guid, player_guid}}
  end

  def at(location) when is_tuple(location) do
    %__MODULE__{selection: :none, destination_location: location}
  end

  def unit_guid(%__MODULE__{selection: {:self, guid}}), do: guid
  def unit_guid(%__MODULE__{selection: {:unit, guid}}), do: guid
  def unit_guid(%__MODULE__{selection: {:corpse, _corpse_guid, player_guid}}), do: player_guid
  def unit_guid(%__MODULE__{}), do: nil

  def item_guid(%__MODULE__{selection: {:item, guid}}), do: guid
  def item_guid(%__MODULE__{}), do: nil

  def object_guid(%__MODULE__{selection: {:object, guid, _access}}), do: guid
  def object_guid(%__MODULE__{}), do: nil

  def ground_location(%__MODULE__{destination_location: location}) when is_tuple(location), do: location
  def ground_location(%__MODULE__{source_location: location}) when is_tuple(location), do: location
  def ground_location(%__MODULE__{}), do: nil
end
