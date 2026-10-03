defmodule ThistleTea.Game.Core.Creature.FireworkGuy do
  @moduledoc """
  vmangos `npc_pats_firework_guy`, the creature a rocket or a rocket cluster
  calls up at a firework launcher to send it off. A rocket bursts three
  yards above the launcher; a cluster fans five rockets around and over it,
  and a large cluster spreads them wider and higher. Whoever fired it earns
  the rocket or cluster credit marker toward the Lunar Festival's firework
  quests, a Lucky Rocket Cluster grants Lunar Fortune three seconds after it
  bursts, and a launch from one of Omen's cluster launchers in Moonglade
  counts toward calling him out of Elune's lake.

  The client's spell data leaves the small red, green, purple, white, and
  yellow cluster rockets without an effect, so vmangos sends nothing up for
  them. Here each launches its color's rocket, as the blue cluster does.
  """

  @rocket_credit 15_893
  @cluster_credit 15_894
  @lunar_fortune 26_522
  @fortune_delay_ms 3_000
  @lifetime_ms 5_000
  @launcher_reach 5.0

  @rockets %{
    blue: {180_854, 180_861},
    green: {180_855, 180_862},
    purple: {180_856, 180_863},
    red: {180_851, 180_860},
    white: {180_857, 180_864},
    yellow: {180_858, 180_865}
  }

  @rocket [{0.0, 0.0, 3.0}]
  @cluster [{0.0, 0.0, 8.0}, {3.5, -1.0, 5.0}, {0.0, 2.0, 5.0}, {0.0, 0.0, 2.0}, {-3.5, -1.0, 5.0}]
  @large_cluster [{0.0, 0.0, 3.0}, {0.0, 3.0, 7.5}, {5.25, -1.5, 7.5}, {-5.25, -1.5, 7.5}, {0.0, 0.0, 12.0}]

  @lucky 15_918

  @guys %{
    15_872 => {:cluster, :blue},
    15_873 => {:cluster, :red},
    15_874 => {:cluster, :green},
    15_875 => {:cluster, :purple},
    15_876 => {:cluster, :white},
    15_877 => {:cluster, :yellow},
    15_879 => {:rocket, :blue},
    15_880 => {:rocket, :green},
    15_881 => {:rocket, :purple},
    15_882 => {:rocket, :red},
    15_883 => {:rocket, :yellow},
    15_884 => {:rocket, :white},
    15_885 => {:large_rocket, :blue},
    15_886 => {:large_rocket, :green},
    15_887 => {:large_rocket, :purple},
    15_888 => {:large_rocket, :red},
    15_889 => {:large_rocket, :white},
    15_890 => {:large_rocket, :yellow},
    15_911 => {:large_cluster, :blue},
    15_912 => {:large_cluster, :green},
    15_913 => {:large_cluster, :purple},
    15_914 => {:large_cluster, :red},
    15_915 => {:large_cluster, :white},
    15_916 => {:large_cluster, :yellow},
    @lucky => {:large_cluster, [:blue, :white, :white, :blue, :blue]}
  }

  def entries, do: Map.keys(@guys)

  def lunar_fortune, do: @lunar_fortune

  def fortune_delay_ms, do: @fortune_delay_ms

  def lifetime_ms, do: @lifetime_ms

  def launcher_reach, do: @launcher_reach

  def launch(entry, {x, y, z}) when is_map_key(@guys, entry) do
    {kind, colors} = Map.fetch!(@guys, entry)
    offsets = offsets(kind)
    colors = if is_list(colors), do: colors, else: List.duplicate(colors, length(offsets))

    fireworks =
      Enum.zip_with(offsets, colors, fn {dx, dy, dz}, color ->
        {rocket(kind, color), {x + dx, y + dy, z + dz, 0.0}}
      end)

    %{
      fireworks: fireworks,
      credit: if(kind in [:cluster, :large_cluster], do: @cluster_credit, else: @rocket_credit),
      lucky?: entry == @lucky
    }
  end

  def launch(_entry, _position), do: nil

  defp offsets(kind) when kind in [:rocket, :large_rocket], do: @rocket
  defp offsets(:cluster), do: @cluster
  defp offsets(:large_cluster), do: @large_cluster

  defp rocket(kind, color) when kind in [:rocket, :cluster], do: elem(Map.fetch!(@rockets, color), 0)
  defp rocket(_kind, color), do: elem(Map.fetch!(@rockets, color), 1)
end
