defmodule ThistleTea.Game.Spell.CorpseTarget do
  @moduledoc "A nearby body and the pure eligibility rules for corpse-dependent spells."

  import Bitwise, only: [&&&: 2]

  alias ThistleTea.Game.Spell

  defstruct [:guid, :kind, :position]

  def range(range, caster_radius, target_radius), do: range + radius(caster_radius) + radius(target_radius)

  def required?(%Spell{} = spell), do: Spell.vmangos_script?(spell, "spell_cannibalize")

  def validate(%Spell{} = spell, corpse) do
    if required?(spell) and not is_struct(corpse, __MODULE__), do: {:error, :no_edible_corpses}, else: :ok
  end

  def eligible?(kind, metadata) when kind in [:player, :mob, :pet, :corpse] and is_map(metadata) do
    not Map.get(metadata, :friendly?, true) and Map.get(metadata, :visible?, false) and
      body?(kind, metadata) and (Map.get(metadata, :unit_flags, 0) &&& 0x00100000) == 0
  end

  def eligible?(_kind, _metadata), do: false

  defp body?(:corpse, %{bones?: true}), do: false
  defp body?(:corpse, %{owner: owner}) when is_integer(owner) and owner > 0, do: true
  defp body?(:player, %{alive?: false, ghost?: false}), do: true
  defp body?(kind, %{alive?: false, creature_type: type}) when kind in [:mob, :pet], do: type in [6, 7]
  defp body?(_kind, _metadata), do: false

  defp radius(value) when is_number(value) and value >= 0, do: value
  defp radius(_value), do: 0.388999998569489
end
