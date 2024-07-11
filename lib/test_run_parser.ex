defmodule MixTcp.TestRunParser do
  @debug false

  def parse(raw_test_run) do
    raw_test_run
    |> String.split("\n")
    |> Stream.reject(&(&1 == ""))
    |> Stream.reject(
      &String.match?(
        &1,
        ~r/Running ExUnit|Finished in|\d+ tests, \d+ failure|excluded|Excluding tags|Including tags/
      )
    )
    |> Stream.reject(&(String.starts_with?(&1, "  * ") && not String.match?(&1, ~r/\d+ms/)))
    |> then(&if @debug, do: debug_parsed_lines(&1), else: &1)
    |> Enum.reduce({false, []}, fn
      "  * " <> s, {false, lines} ->
        tokens = String.split(s)

        time = Enum.at(tokens, -2)
        line = Enum.at(tokens, -1)

        [[_, time_f]] = Regex.scan(~r/\((\d+\.\d+)ms\)/, time)
        [[_, line_i]] = Regex.scan(~r/\[L\#(\d+)\]/, line)

        {false,
         lines ++
           [
             {
               :testcase,
               %{
                 time: String.to_float(time_f),
                 line: String.to_integer(line_i),
                 fail?: false
               }
             }
           ]}

      s, {previous_line_failed_test?, lines} ->
        cond do
          previous_line_failed_test? && String.match?(s, ~r/^\s+test\//) ->
            {false, lines ++ [{:failed_testcase, String.trim(s)}]}

          not previous_line_failed_test? && String.match?(s, ~r/^\s+\d+\) test/) ->
            {true, lines}

          not previous_line_failed_test? && String.match?(s, ~r/^\s+/) ->
            {false, lines}

          not previous_line_failed_test? ->
            {false,
             lines ++
               [
                 {
                   :test_file,
                   s
                   |> String.split(" ")
                   |> Enum.at(1)
                   |> String.trim("[")
                   |> String.trim("]")
                 }
               ]}
        end
    end)
    |> then(fn {false, lines} -> lines end)
    |> Stream.chunk_while(
      [],
      fn
        {:test_file, s}, [] ->
          {:cont, %{test_file: s, testcases: []}}

        {:test_file, s}, acc ->
          {:cont, acc, %{test_file: s, testcases: []}}

        {:testcase, s}, %{testcases: testcases} = acc ->
          {:cont, %{acc | testcases: [s | testcases]}}

        {:failed_testcase, s}, %{test_file: test_file, testcases: [%{line: line} = testcase | rest_testcases]} = acc ->
          [^test_file, line_s] = String.split(s, ":")
          ^line = String.to_integer(line_s)
          {:cont, %{acc | testcases: [%{testcase | fail?: true} | rest_testcases]}}
      end,
      fn
        acc -> {:cont, acc, []}
      end
    )
    |> Stream.flat_map(fn %{test_file: test_file, testcases: testcases} ->
      testcases
      |> Enum.map(fn %{time: time, line: line, fail?: fail?} ->
        %{
          id: :crypto.hash(:md5, "#{test_file}:#{line}") |> Base.encode64(),
          test_file: test_file,
          line: line,
          fail?: fail?,
          duration: time
        }
      end)
    end)
    |> Enum.to_list()
  end

  defp debug_parsed_lines(parsed_lines) do
    tap(parsed_lines, &(&1 |> Enum.join("\n") |> IO.puts()))
  end
end
