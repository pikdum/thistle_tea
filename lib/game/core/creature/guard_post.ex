defmodule ThistleTea.Game.Core.Creature.GuardPost do
  @moduledoc """
  The town guard posts civilians call on, ported from vmangos `GuardMgr`.

  Each listed area names the guard it sends for each team. A post holds ten
  charges, is spent once per call, refuses calls for ten seconds after each
  one, and regains a charge every minute. Recharge is computed from the time
  of the request instead of a ticking timer. Areas without a post leave the
  civilian to rouse the nearest guard instead.

  A civilian shouts a line chosen by its model's race, or failing that its
  faction, except in Razor Hill, where every civilian calls the grunts.
  """

  @max_charges 10
  @cooldown_ms 10_000
  @recharge_ms 60_000
  @razor_hill 362

  defstruct charges: @max_charges, cooldown_until: nil, recharged_at: nil

  @guards %{
    1519 => {68, nil},
    415 => {6087, nil},
    442 => {6086, nil},
    380 => {nil, 3501},
    362 => {nil, 5953},
    513 => {4979, nil},
    1116 => {7939, nil},
    1638 => {nil, 3084},
    221 => {nil, 7975},
    222 => {nil, 7975},
    215 => {nil, 7975},
    1099 => {nil, 8147},
    484 => {nil, 9525},
    367 => {nil, 8017},
    108 => {8096, nil},
    144 => {8055, nil},
    130 => {nil, 7489},
    1497 => {nil, 7980},
    131 => {727, nil},
    1537 => {5595, nil},
    1657 => {4262, nil},
    1637 => {nil, 3296},
    11 => {1475, nil},
    15 => {4979, 10_036},
    496 => {nil, 10_036},
    45 => {10_696, 2621},
    320 => {10_696, nil},
    159 => {nil, 7980},
    85 => {nil, 7980},
    154 => {nil, 7980},
    267 => {2386, 2405},
    271 => {2386, nil},
    272 => {nil, 2405},
    406 => {nil, 7730},
    117 => {nil, 1064},
    87 => {68, nil},
    75 => {nil, 866},
    340 => {nil, 8155},
    69 => {10_037, nil},
    42 => {10_038, nil},
    186 => {3571, nil},
    141 => {3571, nil},
    702 => {4262, nil},
    2361 => {11_822, 11_822},
    3317 => {nil, 14_730},
    2268 => {16_378, 16_378},
    188 => {12_160, nil},
    9 => {1642, nil},
    132 => {853, nil},
    363 => {nil, 5952},
    35 => {4624, 4624},
    2255 => {11_190, 11_190},
    976 => {9460, 9460},
    392 => {3502, 3502},
    228 => {nil, 15_138},
    150 => {15_137, nil},
    321 => {nil, 15_136}
  }

  @human 4403
  @night_elf 4564
  @orc 4561
  @orc_grunts 4558
  @tauren 4560
  @troll 4559
  @dwarf 4583
  @undead 4484
  @gnome 8546

  @model_texts %{
    49 => @human,
    50 => @human,
    51 => @orc,
    52 => @orc,
    53 => @dwarf,
    54 => @dwarf,
    55 => @night_elf,
    56 => @night_elf,
    57 => @undead,
    58 => @undead,
    59 => @tauren,
    60 => @tauren,
    182 => @gnome,
    183 => @gnome,
    185 => @troll,
    186 => @troll
  }

  @faction_texts [
                   {@human,
                    [
                      11,
                      12,
                      123,
                      1078,
                      1575,
                      53,
                      56,
                      84,
                      210,
                      534,
                      1315,
                      149,
                      150,
                      151,
                      894,
                      1075,
                      1077,
                      1096,
                      1577,
                      371,
                      1576
                    ]},
                   {@orc, [29, 65, 85, 125, 1074, 1174, 1595, 1612, 1619, 83, 106, 714, 1034, 1314, 1215, 1515]},
                   {@dwarf, [55, 57, 122, 1611, 1618, 694, 1054, 1055, 1217]},
                   {@gnome, [23, 64, 875]},
                   {@undead, [68, 71, 98, 118, 1134, 1154, 412]},
                   {@night_elf, [79, 80, 124, 1076, 1097, 1594, 1600, 1514]},
                   {@tauren, [104, 105, 995]},
                   {@troll, [126, 876, 877]}
                 ]
                 |> Enum.flat_map(fn {text, factions} -> Enum.map(factions, &{&1, text}) end)
                 |> Map.new()

  def text_ids, do: Enum.uniq([@orc_grunts | Map.values(@model_texts)])

  def guard_entries do
    @guards |> Map.values() |> Enum.flat_map(&Tuple.to_list/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()
  end

  def posted?(area_id), do: Map.has_key?(@guards, area_id)

  def guard(area_id, :alliance), do: @guards |> Map.get(area_id, {nil, nil}) |> elem(0)
  def guard(area_id, :horde), do: @guards |> Map.get(area_id, {nil, nil}) |> elem(1)
  def guard(_area_id, _team), do: nil

  def text_id(@razor_hill, _faction_template_id, _model_id), do: @orc_grunts

  def text_id(_area_id, faction_template_id, model_id),
    do: Map.get(@model_texts, model_id) || Map.get(@faction_texts, faction_template_id)

  def take(%__MODULE__{} = post, now) when is_integer(now) do
    post = recharge(post, now)

    if post.charges > 0 and (is_nil(post.cooldown_until) or now >= post.cooldown_until),
      do: {:ok, %{post | charges: post.charges - 1, cooldown_until: now + @cooldown_ms}},
      else: {:denied, post}
  end

  def recharge(%__MODULE__{recharged_at: nil} = post, now), do: %{post | recharged_at: now}

  def recharge(%__MODULE__{charges: charges} = post, now) when charges >= @max_charges,
    do: %{post | charges: @max_charges, recharged_at: now}

  def recharge(%__MODULE__{} = post, now) do
    gained = div(max(now - post.recharged_at, 0), @recharge_ms)
    charges = min(post.charges + gained, @max_charges)
    recharged_at = if charges == @max_charges, do: now, else: post.recharged_at + gained * @recharge_ms
    %{post | charges: charges, recharged_at: recharged_at}
  end
end
