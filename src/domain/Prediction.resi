// Prediction.resi — public surface of the pure domain ETTL prediction module.
// Exposes the prediction params type and the main predictor function.
open Types

type predictionParams = {
  windowMinutes: option<float>,
  shortWindowMinutes: option<float>,
  now: option<float>,
  windowInfo: option<string>,
}

let predictTimeToLimit: (array<historyPoint>, ~params: predictionParams=?) => float
