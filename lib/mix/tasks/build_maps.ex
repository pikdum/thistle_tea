defmodule Mix.Tasks.BuildMaps do
  use Mix.Task

  @shortdoc "Builds the maps for pathfinding"
  def run(_) do
    wow_dir = System.get_env("WOW_DIR")
    data_dir = Path.join(wow_dir, "Data")
    map_dir = Application.fetch_env!(:thistle_tea, :map_dir)

    case Namigator.build(data_dir, map_dir) do
      true -> Mix.shell().info("Maps built successfully.")
      false -> Mix.shell().error("Failed to build maps.")
    end
  end
end
