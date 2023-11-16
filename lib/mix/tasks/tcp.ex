defmodule Mix.Tasks.Tcp do
  use Mix.Task

  @switches [
    number_of_test_files_to_run: :integer,
    server: :string,
    cookie: :string,
    test_runs_folder: :string
  ]

  @aliases [
    n: :number_of_test_files_to_run,
    s: :server,
    c: :cookie,
    f: :test_runs_folder
  ]

  @impl true
  def run(args) do
    {opts, _files} = OptionParser.parse!(args, strict: @switches, aliases: @aliases)
    server = String.to_atom(opts[:server])

    IO.puts(:stderr, "Running #{opts[:number_of_test_files_to_run]} tests using server #{server} with test runs folder \"#{opts[:test_runs_folder]}\"")

    {:ok, _} = Node.start(build_node_name(), :shortnames)
    Node.set_cookie(String.to_atom(opts[:cookie]))
    Node.connect(server)

    test_files =
      server
      |> :erpc.call(MixTcp.Server, :tcp, [opts[:test_runs_folder]])
      |> Enum.take(opts[:number_of_test_files_to_run])

    Node.stop()

    Mix.Tasks.Test.run([
      "--trace",
      "--no-color"
    ] ++ test_files)
  end

  defp build_node_name do
    random_string = :crypto.strong_rand_bytes(4) |> Base.encode64(padding: false)
    :"mix_tcp_#{random_string}@localhost"
  end

end
