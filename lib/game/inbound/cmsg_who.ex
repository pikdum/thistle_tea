defmodule ThistleTea.Game.Inbound.CmsgWho do
  @moduledoc false
  use ThistleTea.Game.Inbound.ClientMessage, :CMSG_WHO

  alias ThistleTea.Game.Core.Who.Query
  alias ThistleTea.Game.World.Entity.Player.WhoList

  @max_zones 10
  @max_terms 4

  defstruct [:query]

  @impl ClientMessage
  def from_binary(<<level_min::little-size(32), level_max::little-size(32), rest::binary>>) do
    {:ok, name, rest} = BinaryUtils.parse_string(rest)
    {:ok, guild, rest} = BinaryUtils.parse_string(rest)
    <<race_mask::little-size(32), class_mask::little-size(32), rest::binary>> = rest

    with {:ok, zones, rest} <- take_zones(rest),
         {:ok, terms} <- take_terms(rest) do
      %__MODULE__{
        query: %Query{
          level_min: level_min,
          level_max: level_max,
          name: name,
          guild: guild,
          race_mask: race_mask,
          class_mask: class_mask,
          zones: zones,
          terms: terms
        }
      }
    else
      :too_many -> %__MODULE__{}
    end
  end

  @impl ClientMessage
  def handle(%__MODULE__{query: %Query{} = query}, state), do: WhoList.send(state, query)
  def handle(%__MODULE__{}, state), do: state

  defp take_zones(<<count::little-size(32), _rest::binary>>) when count > @max_zones, do: :too_many

  defp take_zones(<<count::little-size(32), rest::binary>>) do
    bytes = count * 4
    <<zones::binary-size(^bytes), rest::binary>> = rest
    {:ok, for(<<zone::little-size(32) <- zones>>, do: zone), rest}
  end

  defp take_terms(<<count::little-size(32), _rest::binary>>) when count > @max_terms, do: :too_many
  defp take_terms(<<count::little-size(32), rest::binary>>), do: {:ok, read_terms(rest, count)}

  defp read_terms(_rest, 0), do: []

  defp read_terms(rest, count) do
    {:ok, term, rest} = BinaryUtils.parse_string(rest)
    [term | read_terms(rest, count - 1)]
  end
end
