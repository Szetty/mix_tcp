defmodule MixTcp.Server do
  @model_params_path "./model_params.bin"

  def tcp(test_runs_folder) do
    Nx.Defn.default_options(compiler: EXLA)
    Nx.global_default_backend(EXLA.Backend)

    test_runs_folder
    |> parse_test_runs()
    |> prepare_data_for_inference()
    |> run_inference(@model_params_path)
  end

  defp parse_test_runs(input_folder) do
    input_folder
    |> File.ls!()
    |> Stream.map(&Path.join(input_folder, &1))
    |> Stream.map(&File.read!/1)
    |> Stream.map(&parse_test_run/1)
  end

  defp prepare_data_for_inference(test_runs_stream) do
    test_file_by_id =
      test_runs_stream
      |> Stream.flat_map(& &1)
      |> Stream.map(&{&1.id, &1.test_file})
      |> Stream.uniq()
      |> Enum.into(%{})

    df =
      test_runs_stream
      |> Stream.with_index()
      |> Stream.flat_map(fn {runs, index} ->
        runs
        |> Enum.map(&Map.put(&1, :cycle, index))
        |> Enum.map(&Map.drop(&1, [:test_file]))
      end)
      |> Enum.group_by(& &1.id)
      |> Enum.map(fn {testcase, runs} ->
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
      |> Explorer.DataFrame.new()

    %{
      test_file_by_id: test_file_by_id,
      df: df
    }
  end

  defp run_inference(%{test_file_by_id: test_file_by_id, df: df}, model_params_path) do
    input_df =
      df
      |> then(&Explorer.DataFrame.put(&1, :cycles, normalize(&1[:cycles])))
      |> then(&Explorer.DataFrame.put(&1, :duration, normalize(&1[:duration])))
      |> then(
        &Explorer.DataFrame.put(&1, :total_runs_count, normalize(&1[:total_runs_count]))
      )

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
    |> Enum.map(fn {testcase, _} -> test_file_by_id[testcase] end)
  end

  defp parse_test_run(raw_test_run) do
    raw_test_run
    |> String.split("\n")
    |> Stream.reject(& &1 == "")
    |> Stream.reject(&String.starts_with?(&1, "Benchmarks.Octo"))
    |> Stream.reject(& String.starts_with?(&1, "  * ") && not String.match?(&1, ~r/\d+ms/))
    |> Stream.map(fn
      "Octo" <> _ = s ->
        {
          :test_file,
          s
          |> String.split(" ")
          |> Enum.at(1)
          |> String.trim("[")
          |> String.trim("]")
        }
      "  * " <> s ->
        {s, fail?} =
          case String.split(s, ";") do
            [s, "F"] ->
              {s, true}
            [s] ->
              {s, false}
          end

        tokens = String.split(s)

        time = Enum.at(tokens, -2)

        [[_, f]] = Regex.scan(~r/\((\d+\.\d+)ms\)/, time)

        {
          :testcase,
          %{time: String.to_float(f), fail?: fail?}
        }
    end)
    |> Stream.chunk_while(
      [],
      fn
        {:test_file, s}, [] ->
          {:cont, %{test_file: s, testcases: []}}
        {:test_file, s}, acc ->
          {:cont, acc, %{test_file: s, testcases: []}}
        {:testcase, s}, %{testcases: testcases} = acc ->
          {:cont, %{acc | testcases: [s | testcases]}}
      end,
      fn
        acc -> {:cont, acc, []}
      end
    )
    |> Stream.map(fn %{test_file: test_file, testcases: testcases} ->
      fail? = Enum.any?(testcases, & &1.fail?)
      duration = testcases |> Enum.map(& &1.time) |> Enum.sum

      %{
        id: :crypto.hash(:md5, test_file) |> Base.encode64(),
        test_file: test_file,
        fail?: fail?,
        duration: duration
      }
    end)
    |> Enum.to_list()
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
