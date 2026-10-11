{:ok, _} = Application.ensure_all_started(:thistle_tea)

Code.require_file("support/population_benchmark.exs", __DIR__)

ThistleTea.Bench.PopulationBenchmark.run()
