defmodule Faction do
  @moduledoc false

  use Ecto.Schema

  @no_reputation_index 4_294_967_295

  @primary_key {:id, :integer, autogenerate: false}
  schema "Faction" do
    field(:reputation_index, :integer)
    field(:reputation_race_mask_0, :integer)
    field(:reputation_race_mask_1, :integer)
    field(:reputation_race_mask_2, :integer)
    field(:reputation_race_mask_3, :integer)
    field(:reputation_class_mask_0, :integer)
    field(:reputation_class_mask_1, :integer)
    field(:reputation_class_mask_2, :integer)
    field(:reputation_class_mask_3, :integer)
    field(:reputation_base_0, :integer)
    field(:reputation_base_1, :integer)
    field(:reputation_base_2, :integer)
    field(:reputation_base_3, :integer)
    field(:reputation_flags_0, :integer)
    field(:reputation_flags_1, :integer)
    field(:reputation_flags_2, :integer)
    field(:reputation_flags_3, :integer)
    field(:parent_faction, :integer)
    field(:name_en_gb, :string)
  end

  def can_have_reputation?(%__MODULE__{reputation_index: reputation_index}) when is_integer(reputation_index) do
    reputation_index >= 0 and reputation_index != @no_reputation_index
  end

  def can_have_reputation?(_faction), do: false
end
