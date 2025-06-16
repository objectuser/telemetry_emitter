defmodule TelemetryEmitter.MixProject do
  use Mix.Project

  @version "0.1.1"

  def project do
    [
      name: "TelemetryEmitter",
      app: :telemetry_emitter,
      version: @version,
      elixir: "~> 1.12",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:telemetry_metrics, "~> 0.6 or ~> 1.0"},
      {:ex_doc, "~> 0.28", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :test, runtime: false}
    ]
  end

  defp docs do
    [
      main: "TelemetryEmitter.Emitter",
      canonical: "http://hexdocs.pm/telemetry_emitter",
      source_url: "https://github.com/objectuser/telemetry_emitter",
      source_ref: "v#{@version}",
      groups_for_modules: [
        "Emitting Metrics": [TelemetryEmitter.Emitter],
        Testing: [TelemetryEmitter.CaptureReporter]
      ]
    ]
  end

  def description do
    """
    Provides a common interface for emitting metrics based on Telemetry events.
    """
  end

  defp package do
    [
      maintainers: ["objectuser"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/objectuser/telemetry_emitter"}
    ]
  end
end
