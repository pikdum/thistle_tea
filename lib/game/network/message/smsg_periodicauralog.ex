defmodule ThistleTea.Game.Network.Message.SmsgPeriodicauralog do
  @moduledoc false
  use ThistleTea.Game.Network.ServerMessage, :SMSG_PERIODICAURALOG

  @periodic_heal 8
  @obs_mod_health 20
  @obs_mod_mana 21
  @periodic_energize 24

  defstruct target: 0,
            caster: 0,
            spell_id: 0,
            auras: []

  @impl ServerMessage
  def to_binary(%__MODULE__{} = message) do
    auras = if is_list(message.auras), do: message.auras, else: []

    BinaryUtils.pack_guid(message.target) <>
      BinaryUtils.pack_guid(message.caster) <>
      <<normalize_integer(message.spell_id)::little-size(32), length(auras)::little-size(32)>> <>
      Enum.map_join(auras, "", &aura_binary/1)
  end

  defp aura_binary(aura) when is_map(aura) do
    type =
      aura
      |> Map.get(:aura_type, Map.get(aura, :type))
      |> aura_type()

    amount = normalize_integer(Map.get(aura, :amount, 0))

    case type do
      value when value in [@periodic_heal, @obs_mod_health] ->
        <<value::little-size(32), amount::little-size(32)>>

      value when value in [@obs_mod_mana, @periodic_energize] ->
        misc_value = normalize_integer(Map.get(aura, :misc_value, 0))
        <<value::little-size(32), misc_value::little-size(32), amount::little-size(32)>>

      value ->
        <<value::little-size(32)>>
    end
  end

  defp aura_binary(_aura), do: <<0::little-size(32)>>

  defp aura_type(:periodic_heal), do: @periodic_heal
  defp aura_type(:obs_mod_health), do: @obs_mod_health
  defp aura_type(:obs_mod_mana), do: @obs_mod_mana
  defp aura_type(:periodic_energize), do: @periodic_energize
  defp aura_type(value) when is_integer(value) and value >= 0, do: value
  defp aura_type(_value), do: 0

  defp normalize_integer(value) when is_integer(value), do: max(value, 0)
  defp normalize_integer(value) when is_float(value), do: value |> trunc() |> max(0)
  defp normalize_integer(_value), do: 0
end
