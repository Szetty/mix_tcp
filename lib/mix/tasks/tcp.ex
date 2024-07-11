defmodule Mix.Tasks.Tcp do
  use Mix.Task

  @switches [
    number_of_tests_to_run: :integer,
    server: :string,
    cookie: :string,
    test_runs_folder: :string
  ]

  @aliases [
    n: :number_of_tests_to_run,
    s: :server,
    c: :cookie,
    f: :test_runs_folder
  ]

  @impl true
  def run(args) do
    _ = Mix.Project.get!()

    {opts, _files} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    server = String.to_atom(opts[:server])

    IO.puts(
      :stderr,
      "Running #{opts[:number_of_tests_to_run]} tests using server #{server} with test runs folder \"#{opts[:test_runs_folder]}\""
    )

    {:ok, _} = Node.start(build_node_name(), :shortnames)
    Node.set_cookie(String.to_atom(opts[:cookie]))
    Node.connect(server)

    tests =
      server
      |> :erpc.call(MixTcp.Server, :tcp, [opts[:test_runs_folder]])
      |> Enum.take(opts[:number_of_tests_to_run])

    Node.stop()

    tests_input = prepare_tests_input(tests)

    IO.puts(
      :stderr,
      "Running the following tests: #{Enum.join(tests_input, " ")}"
    )

    [
      "--trace",
      "--no-color"
    ]
    |> Kernel.++(tests_input)
    |> Mix.Tasks.Test.run()
  end

  defp build_node_name do
    random_string = :crypto.strong_rand_bytes(4) |> Base.encode32(padding: false)
    :"mix_tcp_#{random_string}@localhost"
  end

  defp prepare_tests_input(tests) do
    tests
    |> Enum.group_by(
      fn {test_file, _line} -> test_file end,
      fn {_test_file, line} -> line end
    )
    |> Enum.map(fn {test_file, lines} ->
      "#{test_file}:#{Enum.join(lines, ":")}"
    end)
  end
end
