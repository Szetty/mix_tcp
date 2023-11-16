defmodule MixTcp.MixProject do
  use Mix.Project

  def project do
    [
      app: :mix_tcp,
      version: "1.0.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:axon, "~> 0.5.1"},
      {:exla, "~> 0.5.3"},
      {:explorer, "~> 0.6.1"},
      {:statistex, "~> 1.0"}
    ]
  end
end
