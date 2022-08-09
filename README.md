# TelemetryEmitter

Emit telemetry metrics, mirroring the definition created with
[`Telemetry.Metrics`](https://hexdocs.pm/telemetry_metrics/).

In order to not conflict with the `Telemetry` namespace, the `Emitter` module is
under `TelemetryEmitter.Emitter`.

See the documentation [here](https://hexdocs.pm/telemetry_emitter/).

## Installation

Telemetry Emitter is [available in
Hex](https://hex.pm/packages/telemetry_emitter), the package can be installed by
adding `telemetry_emitter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:telemetry_emitter, "~> 0.1.0"}
  ]
end
```
