defmodule ColdStorage.MixProject do
  use Mix.Project

  def project do
    [
      app: :cold_storage,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:briefly, "~> 0.5.1", only: [:test]}
    ]
  end
end
