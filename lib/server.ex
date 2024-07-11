defmodule MixTcp.Server do
  alias MixTcp.TestRunParser

  @model_params_path "./model_params.bin"

  def tcp(test_runs_folder, cycles \\ :all) do
    Nx.Defn.default_options(compiler: EXLA)
    Nx.global_default_backend(EXLA.Backend)

    test_runs_folder
    |> parse_test_runs(cycles)
    |> prepare_data_for_inference()
    |> run_inference(@model_params_path)
  end

  defp parse_test_runs(input_folder, cycles) do
    input_folder
    |> File.ls!()
    |> Enum.sort()
    |> Stream.map(&Path.join(input_folder, &1))
    |> Stream.map(&File.read!/1)
    |> Stream.map(&TestRunParser.parse/1)
    |> then(
      &if cycles == :all do
        &1
      else
        Stream.take(&1, cycles)
      end
    )
    |> Enum.to_list()
  end

  defp prepare_data_for_inference([]), do: :skip

  defp prepare_data_for_inference(test_runs) do
    test_by_id =
      test_runs
      |> Stream.flat_map(& &1)
      |> Stream.map(&{&1.id, {&1.test_file, &1.line}})
      |> Stream.uniq()
      |> Enum.into(%{})

    df =
      test_runs
      |> Stream.with_index()
      |> Stream.flat_map(fn {runs, index} ->
        runs
        |> Enum.map(&Map.put(&1, :cycle, index))
        |> Enum.map(&Map.drop(&1, [:test_file]))
      end)
      |> Enum.group_by(& &1.id)
      |> Stream.map(fn {testcase, runs} ->
        cycles_count =
          runs
          |> Stream.map(& &1.cycle)
          |> Stream.uniq()
          |> Enum.count()

        duration_avg =
          runs
          |> Stream.map(& &1.duration)
          |> Enum.to_list()
          |> Statistex.average()

        total_runs_count = Enum.count(runs)

        fault_rate =
          runs
          |> Stream.filter(& &1.fail?)
          |> Enum.count()
          |> Kernel./(total_runs_count)

        %{
          testcase: testcase,
          cycles: cycles_count,
          duration: duration_avg,
          total_runs_count: total_runs_count,
          fault_rate: fault_rate
        }
      end)
      |> Stream.filter(&(&1.total_runs_count >= 1))
      |> Enum.to_list()
      |> Explorer.DataFrame.new()

    %{
      test_by_id: test_by_id,
      df: df
    }
  end

  defp run_inference(:skip, _), do: []

  defp run_inference(%{test_by_id: test_by_id, df: df}, model_params_path) do
    input_df =
      df
      |> then(&Explorer.DataFrame.put(&1, :cycles, normalize(&1[:cycles])))
      |> then(&Explorer.DataFrame.put(&1, :duration, normalize(&1[:duration])))
      |> then(&Explorer.DataFrame.put(&1, :total_runs_count, normalize(&1[:total_runs_count])))

    model = build_model()
    model_params = fetch_model_params(model_params_path)

    input_tensor =
      input_df
      |> Explorer.DataFrame.discard([:testcase])
      |> Explorer.DataFrame.names()
      |> Enum.map(&Explorer.Series.to_tensor(df[&1]))
      |> Nx.stack(axis: 1)
      |> Nx.as_type(:f32)

    output =
      Axon.predict(model, model_params, input_tensor)
      |> Nx.to_list()
      |> List.flatten()

    testcases = Explorer.Series.to_list(input_df[:testcase])

    Enum.zip(testcases, output)
    |> Enum.sort_by(fn {_, output} -> -output end)
    |> Enum.map(fn {testcase, _} -> test_by_id[testcase] end)
  end

  defp normalize(series) do
    list = Explorer.Series.to_list(series)
    {min, max} = Enum.min_max(list)
    {new_min, new_max} = {0, 1}

    if min == max do
      list
      |> Enum.map(fn _ -> 0.0 end)
      |> Explorer.Series.from_list()
    else
      list
      |> Enum.map(&(new_min + (&1 - min) / (max - min) * (new_max - new_min)))
      |> Explorer.Series.from_list()
    end
  end

  defp build_model do
    "input"
    |> Axon.input(shape: {nil, 4})
    |> Axon.dense(32, activation: :relu)
    |> Axon.dropout(rate: 0.1)
    |> Axon.dense(32, activation: :relu)
    |> Axon.dropout(rate: 0.1)
    |> Axon.dense(1, activation: :sigmoid)
  end

  defp fetch_model_params(model_params_path) do
    model_params_path
    |> File.read!()
    |> Nx.deserialize()
  end
end
